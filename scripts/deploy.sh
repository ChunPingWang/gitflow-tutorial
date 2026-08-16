#!/usr/bin/env bash
#
# GitFlow 分支 → Kubernetes namespace 部署腳本
# ------------------------------------------------------------
#   ./scripts/deploy.sh                 依當前分支決定環境
#   ./scripts/deploy.sh develop         明確指定分支
#   ./scripts/deploy.sh release/1.1.0
#   ./scripts/deploy.sh main
#
# 分支對應：
#   main / master  →  prod     (3 replicas)
#   release/*      →  staging  (2 replicas)
#   hotfix/*       →  staging  (2 replicas，快速通道)
#   develop        →  dev      (1 replica)
#   feature/*      →  不部署（只跑 CI）
# ------------------------------------------------------------

set -euo pipefail

CLUSTER="${KIND_CLUSTER:-gitflow-demo}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo develop)}"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)"
VERSION="$(cat VERSION 2>/dev/null || echo 0.0.0)"

case "$BRANCH" in
  main|master) NS=prod    ; REPLICAS=3 ; HOST=demo.localtest.me     ; SUFFIX=""     ;;
  release/*)   NS=staging ; REPLICAS=2 ; HOST=stg.demo.localtest.me ; SUFFIX="-rc"  ;;
  hotfix/*)    NS=staging ; REPLICAS=2 ; HOST=stg.demo.localtest.me ; SUFFIX="-hf"  ;;
  develop)     NS=dev     ; REPLICAS=1 ; HOST=dev.demo.localtest.me ; SUFFIX="-dev" ;;
  feature/*)
    echo "ℹ️  feature 分支只跑 CI，不部署到常駐環境"
    echo "   （PR 預覽環境由 CI 在臨時 Kind 叢集上建立）"
    exit 0 ;;
  *)
    echo "❌ 分支 '$BRANCH' 不對應任何環境" >&2
    echo "   合法分支：main / develop / release/* / hotfix/* / feature/*" >&2
    exit 1 ;;
esac

TAG="${VERSION}${SUFFIX}.${SHA}"
IMAGE="demo-app:${TAG}"

echo "────────────────────────────────────────────"
echo "  分支    : $BRANCH"
echo "  環境    : $NS  (replicas=$REPLICAS)"
echo "  映像    : $IMAGE"
echo "  網址    : http://${HOST}:8080"
echo "────────────────────────────────────────────"

# 前置檢查
command -v docker  >/dev/null || { echo "❌ 找不到 docker" >&2; exit 1; }
command -v kind    >/dev/null || { echo "❌ 找不到 kind" >&2; exit 1; }
command -v kubectl >/dev/null || { echo "❌ 找不到 kubectl" >&2; exit 1; }
kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || {
  echo "❌ 找不到 Kind 叢集 '$CLUSTER'" >&2
  echo "   請先執行：kind create cluster --config kind-cluster.yaml" >&2
  exit 1; }

kubectl config use-context "kind-${CLUSTER}" >/dev/null

echo "▶ [1/5] 建置映像"
docker build \
  --build-arg APP_VERSION="$TAG" \
  --build-arg GIT_BRANCH="$BRANCH" \
  --build-arg GIT_SHA="$SHA" \
  --build-arg BUILD_ENV="$NS" \
  -t "$IMAGE" ./app

echo "▶ [2/5] 載入映像到 Kind 節點"
kind load docker-image "$IMAGE" --name "$CLUSTER"

echo "▶ [3/5] 確保 namespace 存在"
kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"
kubectl label namespace "$NS" --overwrite \
  "gitflow-branch=$(echo "$BRANCH" | tr '/' '-')" >/dev/null

echo "▶ [4/5] 套用 manifest"
kubectl -n "$NS" apply -f k8s/base/deployment.yaml
kubectl -n "$NS" apply -f k8s/base/ingress.yaml
kubectl -n "$NS" set image deployment/demo-app "web=${IMAGE}"
kubectl -n "$NS" scale deployment/demo-app --replicas="$REPLICAS"
kubectl -n "$NS" annotate deployment/demo-app \
  "kubernetes.io/change-cause=${BRANCH}@${SHA}" --overwrite >/dev/null
kubectl -n "$NS" patch ingress demo-app --type=json \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/rules/0/host\",\"value\":\"${HOST}\"}]" >/dev/null

echo "▶ [5/5] 等待滾動更新"
if ! kubectl -n "$NS" rollout status deployment/demo-app --timeout=180s; then
  echo "❌ 部署失敗，自動回滾" >&2
  kubectl -n "$NS" rollout undo deployment/demo-app
  kubectl -n "$NS" rollout status deployment/demo-app --timeout=120s
  exit 1
fi

echo
kubectl -n "$NS" get deploy,pod,svc -l app=demo-app
echo
echo "✅ 部署完成"
echo "   http://${HOST}:8080"
echo "   （Ingress 未安裝時可改用：kubectl -n ${NS} port-forward svc/demo-app 8000:80）"

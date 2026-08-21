# Kind + Kubernetes 部署

> 本頁是《[Git 與 GitFlow 教學手冊](../README.md)》的附錄 A。

[← 回手冊首頁](../README.md) ｜ [上一章：多 Pipeline 設計](pipelines.md)

---

## 附錄 A：Kind + Kubernetes 部署

本附錄示範如何在本機用 **Kind**（Kubernetes IN Docker）建立叢集，
並把 GitFlow 的 `develop` / `release` / `main` 分支對應到 `dev` / `staging` / `prod` 三個 namespace。

### A.1 前置需求

```bash
# 必要：容器執行環境（擇一）
# 1) Docker Desktop  →  https://www.docker.com/products/docker-desktop/
# 2) Colima（macOS 輕量替代方案）
brew install colima docker
colima start --cpu 4 --memory 8 --disk 60

# 確認 daemon 有在跑
docker info | head -5
```

> ⚠️ Kind 是「把 Kubernetes 節點跑成 Docker 容器」，**沒有執行中的 Docker/Podman daemon 就無法建立叢集**。

### A.2 安裝 Kind 與 kubectl

```bash
# macOS
brew install kind kubectl

# Linux (amd64)
[ "$(uname -m)" = "x86_64" ] && ARCH=amd64 || ARCH=arm64
curl -Lo ./kind "https://kind.sigs.k8s.io/dl/latest/kind-linux-${ARCH}"
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# 驗證
kind version
kubectl version --client
```

### A.3 建立叢集

`kind-cluster.yaml`：

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: gitflow-demo
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80          # Ingress HTTP
        hostPort: 8080
        protocol: TCP
      - containerPort: 443         # Ingress HTTPS
        hostPort: 8443
        protocol: TCP
  - role: worker
  - role: worker
```

```bash
kind create cluster --config kind-cluster.yaml

# 常用管理指令
kind get clusters
kubectl cluster-info --context kind-gitflow-demo
kubectl get nodes -o wide
kubectl config use-context kind-gitflow-demo

# 刪除
kind delete cluster --name gitflow-demo
```

實機輸出（Kind 0.32）：

```text
NAME                         STATUS   ROLES           AGE   VERSION
gitflow-demo-control-plane   Ready    control-plane   47s   v1.36.1
gitflow-demo-worker          Ready    <none>          33s   v1.36.1
gitflow-demo-worker2         Ready    <none>          34s   v1.36.1
```

> Kubernetes 版本由 Kind 的版本決定（Kind 0.32 → k8s 1.36.1）。
> 要指定版本請用 `kind create cluster --image kindest/node:v1.34.0`。

### A.4 安裝 Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s
```

#### 實測踩到的兩個坑（Kind + ingress-nginx）

**坑 1：controller 被排到 worker 節點，Ingress 完全不通**

`kind-cluster.yaml` 的 `extraPortMappings` 只開在 control-plane 上，但新版的
ingress-nginx kind provider manifest **已經拿掉 `ingress-ready` 的 nodeSelector**，
controller 可能被排到 worker，導致 host 的 8080 埠打不到任何東西。

```bash
# 確認它跑在哪個節點
kubectl -n ingress-nginx get pod -o wide -l app.kubernetes.io/component=controller
# NAME                            ...   NODE
# ingress-nginx-controller-xxx    ...   gitflow-demo-worker      ← ✘ 不通

# 釘回有 port mapping 的節點
kubectl -n ingress-nginx patch deployment ingress-nginx-controller --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/nodeSelector/ingress-ready","value":"true"}]'

kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller
# NAME                            ...   NODE
# ingress-nginx-controller-yyy    ...   gitflow-demo-control-plane   ← ✔ 通了
```

**坑 2：controller 還沒起來就 apply Ingress，被 admission webhook 拒絕**

```text
Error from server (InternalError): failed calling webhook "validate.nginx.ingress.kubernetes.io":
dial tcp 10.96.46.42:443: connect: connection refused
```

controller 的映像要拉 ~110MB，第一次可能等 30 秒以上。
`scripts/deploy.sh` 對此做了**優雅降級**：等不到 controller 就跳過 Ingress，改提示用
`port-forward`，讓部署本身不會因為 Ingress 而失敗。

**坑 3：先 apply 再 patch host，會被判定為 host 重複**

base manifest 裡的 host 只能有一個預設值。若像下面這樣「先 apply、再 patch 成正確的 host」：

```bash
kubectl -n dev apply -f k8s/base/ingress.yaml     # host 還是預設的 demo.localtest.me
kubectl -n dev patch ingress demo-app ...          # 才改成 dev.demo.localtest.me
```

一旦 prod 已經用掉了 `demo.localtest.me`，`apply` 那一步就會被 webhook 擋下：

```text
admission webhook "validate.nginx.ingress.kubernetes.io" denied the request:
host "demo.localtest.me" and path "/" is already defined in ingress prod/demo-app
```

**正解是在 apply 之前就把 host 換好**（`scripts/deploy.sh` 採用的做法）：

```bash
TMP_ING="$(mktemp)"
sed "s|host: .*|host: ${HOST}|" k8s/base/ingress.yaml > "$TMP_ING"
kubectl -n "$NS" apply -f "$TMP_ING"
rm -f "$TMP_ING"
```

> 正式專案請改用 Kustomize 的 overlay 或 Helm 的 values 來做環境差異化，
> 這裡用 `sed` 是為了讓範例不引入額外工具。

驗證三個環境真的各自獨立：

```console
$ for h in dev.demo stg.demo demo; do
    curl -s -H "Host: ${h}.localtest.me" http://localhost:8080/ | grep -oE '<b>[^<]*</b>|<code>[^<]*</code>'
  done

dev.demo.localtest.me      1.2.0-dev.0589c2b   develop         dev
stg.demo.localtest.me      1.1.0-rc.ddf9df0    release/1.1.0   staging
demo.localtest.me          1.1.0.77f1e19       main            prod
```

### A.5 建立對應 GitFlow 的三個環境

```bash
kubectl create namespace dev
kubectl create namespace staging
kubectl create namespace prod

kubectl label namespace dev     gitflow-branch=develop
kubectl label namespace staging gitflow-branch=release
kubectl label namespace prod    gitflow-branch=main

kubectl get ns -L gitflow-branch
```

### A.6 應用程式與 Manifest

`app/Dockerfile`：

```dockerfile
FROM nginx:1.27-alpine
ARG APP_VERSION=dev
ARG GIT_BRANCH=unknown
ARG GIT_SHA=unknown
RUN printf '<!doctype html><html><head><meta charset="utf-8"><title>GitFlow Demo</title></head>\
<body style="font-family:sans-serif;padding:3rem">\
<h1>GitFlow Demo App</h1>\
<p>Version: <b>%s</b></p><p>Branch: <b>%s</b></p><p>Commit: <code>%s</code></p>\
</body></html>' "$APP_VERSION" "$GIT_BRANCH" "$GIT_SHA" > /usr/share/nginx/html/index.html
EXPOSE 80
```

`k8s/base/deployment.yaml`：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  labels:
    app: demo-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
        - name: web
          image: demo-app:dev          # 由 CI 覆寫成實際 tag
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
          resources:
            requests: { cpu: 50m,  memory: 64Mi }
            limits:   { cpu: 200m, memory: 128Mi }
          readinessProbe:
            httpGet: { path: /, port: 80 }
            initialDelaySeconds: 2
            periodSeconds: 5
          livenessProbe:
            httpGet: { path: /, port: 80 }
            initialDelaySeconds: 10
            periodSeconds: 15
---
apiVersion: v1
kind: Service
metadata:
  name: demo-app
spec:
  selector:
    app: demo-app
  ports:
    - port: 80
      targetPort: 80
```

`k8s/base/ingress.yaml`：

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: demo.localtest.me       # localtest.me 一律解析到 127.0.0.1
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: demo-app
                port:
                  number: 80
```

### A.7 一鍵部署腳本

完整腳本見 [`scripts/deploy.sh`](../scripts/deploy.sh)。核心是[前面 C4 Level 4](../README.md#level-4--code關鍵資料結構) 那張分支路由表，
外加五個步驟：建置映像 → `kind load` 進節點 → 套用 manifest → 覆寫映像/replica/host → 等待滾動更新（失敗自動回滾）。

```bash
chmod +x scripts/deploy.sh

git switch develop       && ./scripts/deploy.sh    # → dev     (1 replica)
git switch release/1.1.0 && ./scripts/deploy.sh    # → staging (2 replicas)
git switch main          && ./scripts/deploy.sh    # → prod    (3 replicas)
```

**實機執行結果**

```console
$ ./scripts/deploy.sh develop
────────────────────────────────────────────
  分支    : develop
  環境    : dev  (replicas=1)
  映像    : demo-app:1.0.0-dev.d5059e4
  網址    : http://dev.demo.localtest.me:8080
────────────────────────────────────────────
▶ [1/5] 建置映像
▶ [2/5] 載入映像到 Kind 節點
▶ [3/5] 確保 namespace 存在
▶ [4/5] 套用 manifest
▶ [5/5] 等待滾動更新
deployment "demo-app" successfully rolled out
✅ 部署完成
   http://dev.demo.localtest.me:8080
```

三個分支各部署一次後，三個環境同時線上：

```console
$ kubectl get deploy -A -l app=demo-app \
    -o custom-columns='NAMESPACE:.metadata.namespace,READY:.status.readyReplicas,\
IMAGE:.spec.template.spec.containers[0].image,CHANGE-CAUSE:.metadata.annotations.kubernetes\.io/change-cause'

NAMESPACE   READY   IMAGE                        CHANGE-CAUSE
dev         1       demo-app:1.0.0-dev.d5059e4   develop@d5059e4
staging     2       demo-app:1.1.0-rc.ddf9df0    release/1.1.0@ddf9df0
prod        3       demo-app:1.1.0.77f1e19       main@77f1e19
```

> `CHANGE-CAUSE` 欄位是靠 `kubectl annotate ... kubernetes.io/change-cause` 寫入的。
> 上線出事時，`kubectl rollout history` 一眼就能看出「這一版是從哪個分支的哪個 commit 來的」——
> 這是把 GitFlow 接上 K8s 時最值得做的一件小事。

**三個環境的隔離驗證**

```console
$ for h in dev.demo stg.demo demo; do curl -s -H "Host: ${h}.localtest.me" http://localhost:8080/; done
Version: 1.0.0-dev.d5059e4  Branch: develop        Environment: dev
Version: 1.1.0-rc.ddf9df0   Branch: release/1.1.0  Environment: staging
Version: 1.1.0.77f1e19      Branch: main           Environment: prod
```

映像把「自己來自哪個分支」烙進 `index.html`，所以打開網頁就能確認部署對不對 ——
這是驗證分支策略最直觀的方式。

### A.8 GitHub Actions：GitFlow → K8s 自動部署

完整的 6 條 pipeline 已獨立成[第 15 章](pipelines.md#15-多-pipeline-設計)，
可執行的檔案在 [`ci-examples/github-actions/`](../ci-examples/github-actions/)。與本附錄相關的重點：

| Pipeline | 與 Kind 的關係 |
|----------|---------------|
| ① `feature-ci` | 用 `helm/kind-action` 開**臨時叢集**做 PR 預覽，job 結束即銷毀 |
| ③ `release-cd` | 在臨時叢集跑完整 E2E，再部署到常駐的 staging |
| ⑥ `nightly-e2e` | 用 matrix 在 k8s 1.34 / 1.35 / 1.36 上各跑一次，驗證相容性與回滾機制 |

CI 中建立 Kind 叢集只要三行：

```yaml
      - uses: helm/kind-action@v1
        with:
          cluster_name: ci
          config: kind-cluster.yaml
```

> **不要維護常駐的測試叢集。** PR 預覽與 E2E 用 Kind 隨開隨關，
> 每次都是乾淨環境，成本只有 runner 的幾分鐘，也不會有「測試環境被別人佔用」的問題。


### A.9 K8s 常用除錯指令

```bash
kubectl get all -n dev                        # 該 namespace 全部資源
kubectl get pods -n dev -w                    # 持續觀察 pod 狀態
kubectl describe pod <pod> -n dev             # ★ 看 Events，90% 的問題在這
kubectl logs <pod> -n dev                     # 看日誌
kubectl logs <pod> -n dev --previous          # 看上一個掛掉的容器的日誌
kubectl logs -f deployment/demo-app -n dev    # 持續追蹤
kubectl exec -it <pod> -n dev -- sh           # 進容器
kubectl port-forward svc/demo-app 8000:80 -n dev   # 本機直連 service

kubectl rollout history deployment/demo-app -n dev  # 部署歷史
kubectl rollout undo deployment/demo-app -n dev     # ★ 一鍵回滾
kubectl rollout undo deployment/demo-app -n dev --to-revision=2

kubectl get events -n dev --sort-by=.lastTimestamp  # 依時間排序的事件
kubectl top pods -n dev                             # 資源用量（需 metrics-server）
```

### A.10 Kind 常見問題

| 問題 | 原因 | 解法 |
|------|------|------|
| `failed to connect to the docker API at unix:///var/run/docker.sock` | 沒有執行中的容器 daemon | 啟動 Docker Desktop，或 `colima start --cpu 4 --memory 8 --disk 60` |
| Pod 卡在 `ErrImagePull` | **Kind 節點看不到本機 docker 映像** | `kind load docker-image <image> --name <cluster>` |
| `ImagePullBackOff` 但已 load | `imagePullPolicy: Always` 逼它去 registry 抓 | 改成 `IfNotPresent` |
| **Ingress 回 connection refused** | controller 被排到沒有 port mapping 的 worker | 見 [A.4 坑 1](#實測踩到的兩個坑kind--ingress-nginx)：patch nodeSelector `ingress-ready=true` |
| **apply Ingress 被 webhook 拒絕** | controller 尚未就緒（映像要拉 ~110MB） | `kubectl wait -n ingress-nginx --for=condition=ready pod -l app.kubernetes.io/component=controller` |
| 叢集建立超時 | 記憶體不足 | Docker Desktop / Colima 調高至 ≥ 8GB |
| Pod 一直 `Pending` | 資源不足或無可用節點 | `kubectl describe pod` 看 Events |
| k8s 版本跟預期不同 | 版本由 Kind 版本決定 | `kind create cluster --image kindest/node:v1.34.0` |
| 清理磁碟 | Kind 映像佔空間 | `kind delete cluster --all && docker system prune -af` |
| **Colima：hostPort 打不通** | VM 的 port forwarding 未生效 | `docker port <control-plane>` 確認映射；或改用 `kubectl port-forward` |

---

[← 回手冊首頁](../README.md) ｜ [上一章：多 Pipeline 設計](pipelines.md)

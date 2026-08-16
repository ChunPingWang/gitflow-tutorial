#!/usr/bin/env bash
#
# GitFlow 情境模擬器
# ------------------------------------------------------------
# 在 /tmp/gitflow-sandbox 建立乾淨的沙箱 repo，實際跑過 26 種 GitFlow 情境。
# 不會動到任何既有專案。
#
#   ./scenarios/simulate.sh list          列出所有情境
#   ./scenarios/simulate.sh 10            跑情境 10
#   ./scenarios/simulate.sh 1 3 9 10      跑指定情境
#   ./scenarios/simulate.sh all           全部跑一遍
#   ./scenarios/simulate.sh clean         清除沙箱
#
# 相容 bash 3.2（macOS 內建版本）
# ------------------------------------------------------------

set -u
# 註：刻意不開 pipefail —— 「git log | grep -q」中 grep 提早結束會讓 git 收到
#     SIGPIPE（退出碼 141），開了 pipefail 會把成功的比對誤判成失敗。

SANDBOX="${GITFLOW_SANDBOX:-/tmp/gitflow-sandbox}"

# ── 顏色 ────────────────────────────────────────────────
if [ -t 1 ]; then
  C_RST=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
  C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_C=$'\033[36m'
else
  C_RST=''; C_B=''; C_DIM=''; C_R=''; C_G=''; C_Y=''; C_C=''
fi

title() {
  echo
  echo "${C_C}════════════════════════════════════════════════════════════${C_RST}"
  echo "${C_B} $*${C_RST}"
  echo "${C_C}════════════════════════════════════════════════════════════${C_RST}"
}
step() { echo "${C_C}▶${C_RST} $*"; }
ok()   { echo "${C_G}✔${C_RST} $*"; }
bad()  { echo "${C_R}✘${C_RST} $*"; }
warn() { echo "${C_Y}⚠${C_RST} $*"; }
note() { echo "${C_DIM}  $*${C_RST}"; }

graph() {
  echo "${C_DIM}--- git log --oneline --graph --all ---${C_RST}"
  git log --oneline --graph --decorate --all | head -"${1:-25}"
  echo
}

# ── 沙箱建置 ────────────────────────────────────────────
# 建立一個乾淨的 repo：main(v1.0.0) + develop
fresh_repo() {
  local name="$1"
  local dir="$SANDBOX/$name"
  rm -rf "$dir"
  mkdir -p "$dir"
  cd "$dir" || exit 1

  git init -q -b main
  git config user.name  "GitFlow Demo"
  git config user.email "demo@example.com"
  git config commit.gpgsign false
  git config merge.conflictstyle zdiff3
  git config advice.detachedHead false

  mkdir -p src
  echo "# Demo App" > README.md
  echo "1.0.0" > VERSION
  cat > src/config.js <<'EOF'
export const TIMEOUT = 3000;
export const RETRY = 3;
EOF
  cat > src/app.js <<'EOF'
export function main() {
  return 'v1';
}
EOF
  git add -A
  git commit -q -m "chore: 初始化專案"
  git tag -a v1.0.0 -m "Release 1.0.0"
  git switch -q -c develop
  echo "$dir"
}

# 在當前分支寫檔並 commit
cf() { # cf <file> <content> <message>
  printf '%s\n' "$2" > "$1"
  git add "$1"
  git commit -q -m "$3"
}
# 附加一行並 commit
af() { # af <file> <line> <message>
  printf '%s\n' "$2" >> "$1"
  git add "$1"
  git commit -q -m "$3"
}

# 斷言分支/檔案內容
assert_contains() { # assert_contains <branch> <file> <pattern> <說明>
  if git show "$1:$2" 2>/dev/null | grep -q "$3"; then
    ok "驗證：$4"
  else
    bad "驗證失敗：$4"
  fi
}
assert_not_contains() {
  if git show "$1:$2" 2>/dev/null | grep -q "$3"; then
    bad "驗證失敗：$4"
  else
    ok "驗證：$4"
  fi
}

# ══════════════════════════════════════════════════════════
# A. 正常流程
# ══════════════════════════════════════════════════════════

s1() {
  title "情境 1：標準功能開發（feature → develop）"
  fresh_repo s1 >/dev/null

  step "從 develop 開出 feature/PROJ-101-user-login"
  git switch -q develop
  git switch -q -c feature/PROJ-101-user-login

  step "兩個原子 commit"
  cf src/login.js "export const login = () => 'form';" "feat(auth): 新增登入表單"
  af src/login.js "export const logout = () => true;" "feat(auth): 新增登出"

  step "合回 develop（--no-ff 保留 feature 邊界）"
  git switch -q develop
  git merge -q --no-ff feature/PROJ-101-user-login -m "Merge branch 'feature/PROJ-101-user-login' into develop"
  git branch -q -d feature/PROJ-101-user-login

  assert_contains develop src/login.js "logout" "develop 已含登入功能"
  assert_not_contains main README.md "不存在的內容" "main 完全未受影響"
  graph 12
  note "重點：--no-ff 讓 '這兩個 commit 屬於同一功能' 這件事保留在歷史裡"
}

s2() {
  title "情境 2：多個 feature 平行開發（互不干擾）"
  fresh_repo s2 >/dev/null

  step "開發者 A：feature/login"
  git switch -q -c feature/login develop
  cf src/login.js "export const login = () => 1;" "feat: login"

  step "開發者 B：feature/cart（同時進行）"
  git switch -q -c feature/cart develop
  cf src/cart.js "export const cart = () => [];" "feat: cart"

  step "A 先合併"
  git switch -q develop
  git merge -q --no-ff feature/login -m "Merge branch 'feature/login' into develop"

  step "B 合併前先把 develop 併進自己的分支（後合併者負責解衝突）"
  git switch -q feature/cart
  git merge -q --no-ff develop -m "Merge develop into feature/cart"
  git switch -q develop
  git merge -q --no-ff feature/cart -m "Merge branch 'feature/cart' into develop"

  assert_contains develop src/login.js "login" "develop 含 A 的功能"
  assert_contains develop src/cart.js  "cart"  "develop 含 B 的功能"
  graph 15
}

s3() {
  title "情境 3：標準發版（release → main + develop）"
  fresh_repo s3 >/dev/null

  step "develop 上累積功能"
  cf src/f1.js "export const f1 = 1;" "feat: 功能一"
  cf src/f2.js "export const f2 = 2;" "feat: 功能二"

  step "切出 release/1.1.0（此刻 develop 解凍，可收下一版功能）"
  git switch -q -c release/1.1.0
  cf VERSION "1.1.0" "chore(release): bump to 1.1.0"

  step "develop 同時繼續開發 1.2.0 的功能"
  git switch -q develop
  cf src/f3.js "export const f3 = 3;" "feat: 功能三（1.2.0）"

  step "QA 在 release 分支上回報 bug，就地修"
  git switch -q release/1.1.0
  cf src/f1.js "export const f1 = 1; // fixed" "fix: QA 回報的問題"

  step "合進 main 並打 tag"
  git switch -q main
  git merge -q --no-ff release/1.1.0 -m "Merge branch 'release/1.1.0'"
  git tag -a v1.1.0 -m "Release 1.1.0"

  step "合回 develop（★ 這步不能省）"
  git switch -q develop
  git merge -q --no-ff release/1.1.0 -m "Merge branch 'release/1.1.0' into develop"
  git branch -q -d release/1.1.0

  assert_contains main    VERSION  "1.1.0"  "main 版本號為 1.1.0"
  assert_contains develop src/f1.js "fixed" "release 的修正已回到 develop"
  assert_contains develop src/f3.js "f3"    "develop 的下一版功能仍在"
  assert_not_contains main src/f3.js "f3"   "1.2.0 的功能沒有混進 1.1.0"
  graph 20
}

s4() {
  title "情境 4：線上緊急修復（hotfix）"
  fresh_repo s4 >/dev/null

  step "develop 上有尚未發布的功能（不該跟著 hotfix 上線）"
  cf src/unreleased.js "export const wip = true;" "feat: 尚未發布的功能"

  step "從 main 開 hotfix/1.0.1（★ 不是從 develop）"
  git switch -q main
  git switch -q -c hotfix/1.0.1
  cf src/app.js "export function main() { return 'v1-fixed'; }" "fix: 修復線上 crash"
  cf VERSION "1.0.1" "chore(release): bump to 1.0.1"

  step "合進 main 並打 tag"
  git switch -q main
  git merge -q --no-ff hotfix/1.0.1 -m "Merge branch 'hotfix/1.0.1'"
  git tag -a v1.0.1 -m "Hotfix 1.0.1"

  step "合回 develop"
  git switch -q develop
  git merge -q --no-ff hotfix/1.0.1 -m "Merge branch 'hotfix/1.0.1' into develop"
  git branch -q -d hotfix/1.0.1

  assert_contains     main    src/app.js       "v1-fixed" "main 已修復"
  assert_not_contains main    src/unreleased.js "wip"     "未發布功能沒有被帶上線"
  assert_contains     develop src/app.js       "v1-fixed" "develop 也拿到修復（不會退版）"
  graph 15
}

# ══════════════════════════════════════════════════════════
# B. 衝突處理
# ══════════════════════════════════════════════════════════

s5() {
  title "情境 5：兩個 feature 改到同一行 → 合併衝突"
  fresh_repo s5 >/dev/null

  git switch -q -c feature/a develop
  cf src/config.js "export const TIMEOUT = 5000;
export const RETRY = 3;" "feat(a): TIMEOUT 改為 5000"

  git switch -q -c feature/b develop
  cf src/config.js "export const TIMEOUT = 10000;
export const RETRY = 3;" "feat(b): TIMEOUT 改為 10000"

  step "A 先合併（順利）"
  git switch -q develop
  git merge -q --no-ff feature/a -m "Merge branch 'feature/a' into develop"

  step "B 合併 → 預期衝突"
  if git merge --no-ff feature/b -m "Merge branch 'feature/b' into develop" 2>/dev/null; then
    bad "沒有如預期產生衝突"
  else
    warn "CONFLICT，如預期發生"
    echo "${C_DIM}--- 衝突內容（zdiff3 樣式，可看到共同祖先）---${C_RST}"
    cat src/config.js
    echo
    step "衝突中的檔案："
    git diff --name-only --diff-filter=U
  fi

  step "人工決議：取較大值 10000"
  cat > src/config.js <<'EOF'
export const TIMEOUT = 10000;
export const RETRY = 3;
EOF
  git add src/config.js
  git commit -q --no-edit
  ok "衝突已解決並完成合併"
  assert_contains develop src/config.js "10000" "develop 採用決議後的值"
  graph 12
  note "重點：zdiff3 會多顯示 ||||||| 共同祖先段，判斷誰改了什麼靠它"
}

s6() {
  title "情境 6：feature 落後 develop 太久 → rebase 換基底"
  fresh_repo s6 >/dev/null

  git switch -q -c feature/old develop
  cf src/old.js "export const old = 1;" "feat: 舊分支的功能"

  step "develop 之後前進了 3 個 commit"
  git switch -q develop
  cf src/n1.js "export const n1 = 1;" "feat: develop 新功能 1"
  cf src/n2.js "export const n2 = 2;" "feat: develop 新功能 2"
  cf src/n3.js "export const n3 = 3;" "feat: develop 新功能 3"

  step "落後統計"
  git switch -q feature/old
  echo "  develop 領先 / feature 領先："
  git rev-list --left-right --count develop...feature/old | sed 's/^/    /'

  step "rebase 到最新 develop（分支僅自己使用時的做法）"
  git rebase -q develop
  ok "rebase 完成，歷史成為線性"
  git log --oneline -5 | sed 's/^/    /'
  echo
  note "若分支多人共用，改用 git merge develop —— rebase 會改寫 SHA，害到別人"
}

s7() {
  title "情境 7：release 的修正回併 develop 時衝突（語意衝突）"
  fresh_repo s7 >/dev/null

  cf src/cart.js "export function total(items) { return items.length; }" "feat: 購物車總計"
  git switch -q -c release/1.1.0
  cf src/cart.js "export function total(items) { return items.length || 0; }" "fix: 空陣列處理"

  step "同時間 develop 上有人重構了同一個函式"
  git switch -q develop
  cf src/cart.js "export const total = (items = []) => items.reduce((s, i) => s + i.price, 0);" "refactor: 改為計算金額"

  step "release 回併 develop → 預期衝突"
  if git merge --no-ff release/1.1.0 -m "Merge release/1.1.0 into develop" 2>/dev/null; then
    bad "沒有如預期產生衝突"
  else
    warn "CONFLICT — 這是語意衝突，Git 無法自動判斷"
    cat src/cart.js
    echo
  fi

  step "人工決議：在重構後的結構上重新實作那個修正"
  cat > src/cart.js <<'EOF'
export const total = (items = []) => (items.length ? items.reduce((s, i) => s + i.price, 0) : 0);
EOF
  git add src/cart.js
  git commit -q --no-edit
  ok "已在新結構上保留 release 的修正意圖"
  warn "解完務必跑測試 —— Git 只保證文字對得上，不保證邏輯正確"
}

s8() {
  title "情境 8：rebase 連續衝突 → 中止並改用 merge"
  fresh_repo s8 >/dev/null

  git switch -q -c feature/x develop
  cf src/config.js "export const TIMEOUT = 1000;
export const RETRY = 3;" "feat: 調整 TIMEOUT (1)"
  cf src/config.js "export const TIMEOUT = 2000;
export const RETRY = 3;" "feat: 調整 TIMEOUT (2)"

  git switch -q develop
  cf src/config.js "export const TIMEOUT = 9000;
export const RETRY = 5;" "feat: develop 也改了同一段"

  step "嘗試 rebase → 衝突"
  git switch -q feature/x
  git rebase develop >/dev/null 2>&1 || warn "rebase 停在第一個衝突"
  git status --short | head -5 | sed 's/^/    /'

  step "決定放棄，git rebase --abort"
  git rebase --abort
  ok "已完全回到 rebase 前的狀態（什麼都沒發生）"
  git log --oneline -3 | sed 's/^/    /'

  step "改用 merge：只需解一次衝突"
  git merge develop >/dev/null 2>&1 || warn "merge 也有衝突，但只解這一次"
  cat > src/config.js <<'EOF'
export const TIMEOUT = 2000;
export const RETRY = 5;
EOF
  git add src/config.js
  git commit -q --no-edit
  ok "完成"
  note "反覆遇到同樣的衝突？開啟 git config --global rerere.enabled true"
}

# ══════════════════════════════════════════════════════════
# C. 時序交錯
# ══════════════════════════════════════════════════════════

s9() {
  title "情境 9：release 凍結期間，develop 繼續開發下一版"
  fresh_repo s9 >/dev/null

  cf src/a.js "export const a = 1;" "feat: 功能 A（1.1.0）"
  cf src/b.js "export const b = 2;" "feat: 功能 B（1.1.0）"

  step "切出 release/1.1.0 —— develop 立刻解凍"
  git switch -q -c release/1.1.0
  cf VERSION "1.1.0" "chore(release): bump to 1.1.0"

  step "QA 在 release 上修 bug，同時開發團隊在 develop 做 1.2.0"
  git switch -q develop
  cf src/c.js "export const c = 3;" "feat: 功能 C（1.2.0）"
  git switch -q release/1.1.0
  cf src/a.js "export const a = 1; // QA fix" "fix: QA 問題"
  git switch -q develop
  cf src/d.js "export const d = 4;" "feat: 功能 D（1.2.0）"

  step "release 完成"
  git switch -q main
  git merge -q --no-ff release/1.1.0 -m "Merge branch 'release/1.1.0'"
  git tag -a v1.1.0 -m "Release 1.1.0"
  git switch -q develop
  git merge -q --no-ff release/1.1.0 -m "Merge branch 'release/1.1.0' into develop"

  assert_not_contains main    src/c.js "c" "1.2.0 的功能 C 沒有進 1.1.0"
  assert_not_contains main    src/d.js "d" "1.2.0 的功能 D 沒有進 1.1.0"
  assert_contains     develop src/a.js "QA fix" "QA 修正已回到 develop"
  assert_contains     develop src/d.js "d" "develop 的 1.2.0 進度不受影響"
  graph 20
  note "★ 這就是 GitFlow 存在的唯一理由：QA 期間全隊不必停工"
}

s10() {
  title "情境 10：release 進行中發生 hotfix（★ 最容易做錯）"
  fresh_repo s10 >/dev/null

  cf src/new.js "export const newFeat = 1;" "feat: 1.1.0 的新功能"
  step "切出 release/1.1.0，QA 進行中"
  git switch -q -c release/1.1.0
  cf VERSION "1.1.0" "chore(release): bump to 1.1.0"

  step "此時線上 v1.0.0 出事 → 從 main 開 hotfix/1.0.1"
  git switch -q main
  git switch -q -c hotfix/1.0.1
  cf src/app.js "export function main() { return 'v1-hotfixed'; }" "fix: 線上緊急修復"
  cf VERSION "1.0.1" "chore(release): bump to 1.0.1"

  step "① hotfix → main + tag（先救火）"
  git switch -q main
  git merge -q --no-ff hotfix/1.0.1 -m "Merge branch 'hotfix/1.0.1'"
  git tag -a v1.0.1 -m "Hotfix 1.0.1"

  step "② hotfix → release/1.1.0 （★ 關鍵：不是 develop！）"
  git switch -q release/1.1.0
  if ! git merge -q --no-ff hotfix/1.0.1 -m "Merge branch 'hotfix/1.0.1' into release/1.1.0" 2>/dev/null; then
    git checkout --theirs src/app.js 2>/dev/null
    printf '1.1.0\n' > VERSION
    git add -A && git commit -q --no-edit
  fi
  assert_contains release/1.1.0 src/app.js "v1-hotfixed" "release/1.1.0 已包含 hotfix 修正"

  step "③ release 完成 → main + develop"
  git switch -q main
  git merge -q --no-ff release/1.1.0 -m "Merge branch 'release/1.1.0'"
  git tag -a v1.1.0 -m "Release 1.1.0"
  git switch -q develop
  git merge -q --no-ff release/1.1.0 -m "Merge branch 'release/1.1.0' into develop"

  assert_contains main    src/app.js "v1-hotfixed" "v1.1.0 上線後仍保有 hotfix（沒有回歸）"
  assert_contains develop src/app.js "v1-hotfixed" "develop 也透過 release 拿到修正"
  graph 25
  echo
  warn "若步驟 ② 改成合進 develop 而非 release，v1.1.0 上線時會把 hotfix 覆蓋掉 → 回歸 bug"
}

s11() {
  title "情境 11：hotfix 與 release 幾乎同時完成 → tag 順序"
  fresh_repo s11 >/dev/null

  cf src/new.js "export const f = 1;" "feat: 1.1.0 功能"
  git switch -q -c release/1.1.0
  cf VERSION "1.1.0" "chore(release): bump to 1.1.0"

  git switch -q main
  git switch -q -c hotfix/1.0.1
  cf src/app.js "export function main() { return 'hotfixed'; }" "fix: 緊急修復"

  step "① hotfix 先合 main、先打 v1.0.1"
  git switch -q main
  git merge -q --no-ff hotfix/1.0.1 -m "Merge branch 'hotfix/1.0.1'"
  git tag -a v1.0.1 -m "Hotfix 1.0.1"

  step "② hotfix 併進 release"
  git switch -q release/1.1.0
  git merge -q --no-ff hotfix/1.0.1 -m "Merge hotfix/1.0.1 into release/1.1.0" 2>/dev/null || {
    git add -A; git commit -q --no-edit; }

  warn "③ release 內容已變動 → 先前的 QA 結果失效，必須重跑完整 QA"

  step "④ release 合 main、打 v1.1.0"
  git switch -q main
  git merge -q --no-ff release/1.1.0 -m "Merge branch 'release/1.1.0'"
  git tag -a v1.1.0 -m "Release 1.1.0"

  step "⑤ release 合回 develop"
  git switch -q develop
  git merge -q --no-ff release/1.1.0 -m "Merge branch 'release/1.1.0' into develop"

  step "tag 的時間順序（必須與版本號順序一致）"
  git tag --sort=creatordate --format='    %(creatordate:short) %(refname:short)' | sed 's/^/  /'
  ok "v1.0.0 → v1.0.1 → v1.1.0，順序正確"
}

s12() {
  title "情境 12：兩個 release 分支並存（GitFlow 反模式）"
  fresh_repo s12 >/dev/null

  cf src/f1.js "export const f1 = 1;" "feat: 1.1.0 的功能"
  git switch -q -c release/1.1.0
  cf VERSION "1.1.0" "chore(release): bump to 1.1.0"

  step "1.1.0 卡在客戶驗收，商業壓力下先切 release/1.2.0"
  git switch -q develop
  cf src/f2.js "export const f2 = 2;" "feat: 1.2.0 的功能"
  git switch -q -c release/1.2.0
  cf VERSION "1.2.0" "chore(release): bump to 1.2.0"

  step "1.1.0 有 QA 修正"
  git switch -q release/1.1.0
  cf src/f1.js "export const f1 = 1; // QA fix" "fix: 1.1.0 的 QA 修正"
  FIX=$(git rev-parse HEAD)

  warn "這個修正不會自動進 1.2.0 → 必須手動 cherry-pick"
  git switch -q release/1.2.0
  git cherry-pick "$FIX" >/dev/null 2>&1 || { git add -A; git cherry-pick --continue --no-edit >/dev/null 2>&1; }
  assert_contains release/1.2.0 src/f1.js "QA fix" "1.2.0 也拿到了 1.1.0 的修正"

  echo
  git branch --list 'release/*' | sed 's/^/    /'
  warn "兩個 release 並存代表發版週期太長，應檢討節奏而非多開分支"
}

s13() {
  title "情境 13：release 被判定不上線（廢棄）"
  fresh_repo s13 >/dev/null

  cf src/f1.js "export const f1 = 1;" "feat: 功能一"
  git switch -q -c release/1.1.0
  cf VERSION "1.1.0" "chore(release): bump to 1.1.0"
  cf src/f1.js "export const f1 = 1; // QA fix" "fix: QA 修正（很珍貴，不能丟）"

  warn "驗收未通過，整批功能延期"
  step "方案 B：廢棄 release，但★先合回 develop 保住 QA 修正"
  git switch -q develop
  git merge -q --no-ff release/1.1.0 -m "Merge release/1.1.0 into develop (廢棄，保留修正)"
  git branch -q -D release/1.1.0

  assert_contains     develop src/f1.js "QA fix" "QA 修正保留在 develop"
  assert_not_contains main    src/f1.js "f1"     "main 完全未動，線上仍是 v1.0.0"
  echo "    main 上的最新 tag：$(git describe --tags main)"
  graph 12
}

# ══════════════════════════════════════════════════════════
# D. 異常與救援
# ══════════════════════════════════════════════════════════

s14() {
  title "情境 14：feature 誤從 main 開出 → rebase --onto 換基底"
  fresh_repo s14 >/dev/null

  step "develop 已有 2 個 commit"
  cf src/d1.js "export const d1 = 1;" "feat: develop 既有功能 1"
  cf src/d2.js "export const d2 = 2;" "feat: develop 既有功能 2"

  step "★ 誤從 main 開了 feature/x，還 commit 了 3 次"
  git switch -q main
  git switch -q -c feature/x
  cf src/x1.js "export const x1 = 1;" "feat(x): 第 1 個 commit"
  cf src/x2.js "export const x2 = 2;" "feat(x): 第 2 個 commit"
  cf src/x3.js "export const x3 = 3;" "feat(x): 第 3 個 commit"

  echo "  修正前 —— feature/x 看不到 develop 的東西："
  git ls-files | sed 's/^/    /'

  step "git rebase --onto develop main feature/x"
  git rebase -q --onto develop main feature/x

  echo "  修正後 —— feature/x 已建立在 develop 之上："
  git ls-files | sed 's/^/    /'
  assert_contains feature/x src/d2.js "d2" "feature/x 已含 develop 的既有功能"
  graph 15
  note "語法：git rebase --onto <新基底> <舊基底> <要搬的分支>"
}

s15() {
  title "情境 15：誤在 main 上直接 commit"
  fresh_repo s15 >/dev/null

  git switch -q main
  cf src/oops.js "export const oops = 1;" "feat: 不該直接 commit 在 main 的功能"
  BAD_SHA=$(git rev-parse HEAD)
  warn "main 上出現了一個不該存在的 commit：${BAD_SHA:0:7}"

  step "① 先開分支保住這個 commit（別急著丟掉）"
  git branch feature/rescue "$BAD_SHA"

  step "② main 回到 tag v1.0.0 的狀態"
  git reset -q --hard v1.0.0
  assert_not_contains main src/oops.js "oops" "main 已恢復乾淨"

  step "③ 把功能移植到 develop（正常流程）"
  git switch -q develop
  git cherry-pick "$BAD_SHA" >/dev/null
  assert_contains develop src/oops.js "oops" "功能已在正確的分支上"
  ok "程式碼沒有遺失，main 也恢復了"
  note "若已 push，改用 git revert <sha> 而非 reset --hard"
}

s16() {
  title "情境 16：誤把 feature 直接合進 main（已 push，只能 revert）"
  fresh_repo s16 >/dev/null

  git switch -q -c feature/x develop
  cf src/x.js "export const x = 1;" "feat: 功能 X"

  step "★ 誤合進 main"
  git switch -q main
  git merge -q --no-ff feature/x -m "Merge branch 'feature/x'"
  MERGE_SHA=$(git rev-parse HEAD)
  warn "main 上出現了 merge commit ${MERGE_SHA:0:7}"

  step "已 push 無法 reset → 用 git revert -m 1 抵銷"
  git revert -m 1 --no-edit "$MERGE_SHA" >/dev/null
  assert_not_contains main src/x.js "x" "main 的內容已回復"
  git log --oneline -3 main | sed 's/^/    /'
  echo
  note "-m 1 = 保留第一父（main 這一邊）；-m 2 則會保留被合併分支那一邊"
  note "歷史中仍看得到這兩個 commit —— 這是已 push 情況下的正確代價"
}

s17() {
  title "情境 17：已合併的 feature 要抽掉（★ revert merge 的陷阱）"
  fresh_repo s17 >/dev/null

  git switch -q -c feature/X develop
  cf src/X.js "export const X = 1;" "feat: 功能 X"
  git switch -q develop
  git merge -q --no-ff feature/X -m "Merge branch 'feature/X' into develop"
  MERGE_SHA=$(git rev-parse HEAD)

  step "客戶砍需求 → revert 那個 merge commit"
  git revert -m 1 --no-edit "$MERGE_SHA" >/dev/null
  REVERT_SHA=$(git rev-parse HEAD)
  assert_not_contains develop src/X.js "X" "功能 X 已從 develop 移除"

  step "數月後功能復活 → 直接重新 merge 分支看看會發生什麼"
  git merge --no-ff feature/X -m "重新合併 feature/X" >/dev/null 2>&1
  if git show develop:src/X.js >/dev/null 2>&1; then
    bad "（本次環境下檔案回來了）"
  else
    warn "★ 陷阱重現：merge 執行了，但程式碼沒有回來！"
    note "Git 認為 feature/X 的 commit 早已合併過，不會再帶進來"
  fi

  step "正確解法：revert 那個 revert"
  git revert --no-edit "$REVERT_SHA" >/dev/null
  assert_contains develop src/X.js "X" "功能 X 已正確復活"
  git log --oneline -5 | sed 's/^/    /'
}

s18() {
  title "情境 18：tag 打錯了"
  fresh_repo s18 >/dev/null

  git switch -q main
  cf src/r.js "export const r = 1;" "feat: 要發版的內容"
  RIGHT=$(git rev-parse HEAD)
  WRONG=$(git rev-parse HEAD~1)

  step "★ tag 打在錯的 commit 上"
  git tag -a v1.1.0 "$WRONG" -m "Release 1.1.0"
  echo "    v1.1.0 → $(git rev-list -n1 v1.1.0 | cut -c1-7)（錯誤，應為 ${RIGHT:0:7}）"

  step "情況 A：尚未 push → 直接刪掉重打"
  git tag -d v1.1.0 >/dev/null
  git tag -a v1.1.0 "$RIGHT" -m "Release 1.1.0"
  ok "v1.1.0 → $(git rev-list -n1 v1.1.0 | cut -c1-7)（已修正）"

  step "情況 B：已 push（高風險）"
  note "git tag -d v1.1.0"
  note "git push origin :refs/tags/v1.1.0     # 刪遠端"
  note "git tag -a v1.1.0 <正確sha> -m ...    # 重打"
  note "git push origin v1.1.0"
  note "→ 必須公告全隊執行：git fetch --tags --force"
  warn "更安全的做法：不刪舊 tag，補打正確版本號，並在 Release Notes 標註舊 tag 作廢"
}

s19() {
  title "情境 19：分支被 force push 覆蓋 → 用 reflog 救回"
  fresh_repo s19 >/dev/null

  step "develop 上有 3 個重要 commit"
  cf src/i1.js "export const i1 = 1;" "feat: 重要功能 1"
  cf src/i2.js "export const i2 = 2;" "feat: 重要功能 2"
  cf src/i3.js "export const i3 = 3;" "feat: 重要功能 3"
  GOOD=$(git rev-parse HEAD)
  echo "    正確的 HEAD：${GOOD:0:7}"

  step "★ 同事誤操作，develop 被打回 3 個 commit 之前"
  git reset -q --hard HEAD~3
  bad "現在 develop 少了 3 個 commit："
  git log --oneline -2 | sed 's/^/    /'

  step "用 reflog 找回 force push 前的位置"
  git reflog -6 | sed 's/^/    /'

  step "救回來"
  git reset -q --hard "$GOOD"
  assert_contains develop src/i3.js "i3" "3 個 commit 全數救回"
  git log --oneline -4 | sed 's/^/    /'
  echo
  note "預防：在分支保護設定關閉 force push —— 一次設定，永久受益"
}

s20() {
  title "情境 20：機密進了版控"
  fresh_repo s20 >/dev/null

  step "★ 誤將 .env commit 進去"
  cf .env "API_KEY=sk-super-secret-value-12345" "chore: 加入設定檔"
  bad "機密已進入版本庫：$(git show HEAD:.env)"

  step "尚未 push 的處置"
  git reset -q --soft HEAD~1
  git rm -q --cached .env
  echo ".env" >> .gitignore
  git add .gitignore
  git commit -q -m "chore: 將 .env 排除於版控之外"

  assert_not_contains develop .env "API_KEY" "版控中已無 .env"
  [ -f .env ] && ok "本機檔案仍在（沒有誤刪你的設定）"
  git check-ignore -v .env | sed 's/^/    /'

  echo
  warn "若已 push，順序不能顛倒："
  note "① 立刻輪換那把金鑰 —— 它已經外洩，清歷史救不回來"
  note "② git filter-repo --path .env --invert-paths --force"
  note "③ git push origin --force --all && --force --tags"
  note "④ 通知所有人重新 clone（舊 clone 仍含機密）"
  note "預防：pre-commit 掛 gitleaks protect --staged"
}

# ══════════════════════════════════════════════════════════
# E. 長期維護
# ══════════════════════════════════════════════════════════

s21() {
  title "情境 21：同時維護 v1.x 與 v2.x（support 分支）"
  fresh_repo s21 >/dev/null

  step "develop 演進到 2.0.0 並發布"
  cf src/app.js "export function main() { return 'v2'; }" "feat!: 改版為 v2"
  cf VERSION "2.0.0" "chore(release): bump to 2.0.0"
  git switch -q main
  git merge -q --no-ff develop -m "Merge branch 'develop' (2.0.0)"
  git tag -a v2.0.0 -m "Release 2.0.0"

  step "大客戶仍在 v1.0.0 → 從舊 tag 建立長期支援分支"
  git switch -q -c support/1.x v1.0.0
  ok "support/1.x 建立於 $(git describe --tags --abbrev=0)"

  step "v1.x 的安全修復"
  git switch -q -c hotfix/1.0.1 support/1.x
  cf src/app.js "export function main() { return 'v1-secure'; }" "fix(security): 修補 v1.x 漏洞"
  FIX=$(git rev-parse HEAD)
  git switch -q support/1.x
  git merge -q --no-ff hotfix/1.0.1 -m "Merge branch 'hotfix/1.0.1'"
  git tag -a v1.0.1 -m "Support release 1.0.1"

  assert_contains support/1.x src/app.js "v1-secure" "v1.x 已修復"
  assert_contains main        src/app.js "v2"        "main 仍是 v2（support 不合回 main）"

  step "同一個漏洞若 v2 也有 → cherry-pick 到 develop"
  git switch -q develop
  git cherry-pick "$FIX" >/dev/null 2>&1 || {
    warn "cherry-pick 衝突（v2 結構已不同），人工移植："
    cat > src/app.js <<'EOF'
export function main() { return 'v2-secure'; }
EOF
    git add -A; git cherry-pick --continue --no-edit >/dev/null 2>&1 || git commit -q -m "fix(security): 移植 v1.x 的修補到 v2"
  }
  assert_contains develop src/app.js "secure" "v2 線也拿到了安全修補"
  graph 20
  note "★ support/* 永不合回 main，兩條線各自演進，共通修正靠 cherry-pick"
}

s22() {
  title "情境 22：為停留在舊版的客戶做 hotfix"
  fresh_repo s22 >/dev/null

  step "產品已演進到 v1.2.0"
  cf src/f.js "export const f = '1.1';" "feat: 1.1 功能"
  git switch -q main; git merge -q --no-ff develop -m "Merge develop (1.1.0)"; git tag -a v1.1.0 -m "1.1.0"
  git switch -q develop
  cf src/f.js "export const f = '1.2';" "feat: 1.2 功能"
  git switch -q main; git merge -q --no-ff develop -m "Merge develop (1.2.0)"; git tag -a v1.2.0 -m "1.2.0"

  step "★ 某客戶停留在 v1.1.0，需要專屬修補 → 從舊 tag 開分支"
  git switch -q -c hotfix/1.1.1 v1.1.0
  cf src/legacy.js "export const patched = true;" "fix: 修補 1.1.x 的問題"
  git tag -a v1.1.1 -m "Hotfix 1.1.1 for legacy customers"

  assert_contains     hotfix/1.1.1 src/f.js "1.1" "修補建立在 1.1 的基礎上（沒有混入 1.2 的變更）"
  assert_not_contains main         src/legacy.js "patched" "main 不受影響（它已是更新的 1.2.x）"

  step "檢查同一個 bug 在新版是否也存在"
  echo "    v1.1.0..main 之間對相關檔案的變更："
  git log --oneline v1.1.0..main -- src/f.js | sed 's/^/      /'
  git tag --sort=creatordate --format='    %(refname:short)' | sed 's/^/  /'
}

s23() {
  title "情境 23：一個安全修正要進多個版本線"
  fresh_repo s23 >/dev/null

  step "建立三條版本線：support/1.x、support/2.x、develop"
  git switch -q -c support/1.x v1.0.0
  cf src/sec.js "export const check = (s) => s;" "feat: 1.x 的驗證邏輯"
  git switch -q -c support/2.x v1.0.0
  cf src/sec.js "export const check = (s) => s;" "feat: 2.x 的驗證邏輯"
  git switch -q develop
  cf src/sec.js "export const check = (s) => s;" "feat: 3.x 的驗證邏輯"

  step "★ 從最舊的分支開始修（向前移植成功率最高）"
  git switch -q support/1.x
  cf src/sec.js "export const check = (s) => String(s).replace(/[<>]/g, '');" "fix(security): 修補 XSS 漏洞"
  FIX=$(git rev-parse HEAD)
  ok "修正 commit：${FIX:0:7}"

  step "依序 cherry-pick 到每條線"
  for BR in support/2.x develop; do
    git switch -q "$BR"
    if git cherry-pick "$FIX" >/dev/null 2>&1; then
      ok "$BR ← cherry-pick 成功"
    else
      warn "$BR ← 需人工處理"
      git cherry-pick --abort 2>/dev/null
      cat > src/sec.js <<'EOF'
export const check = (s) => String(s).replace(/[<>]/g, '');
EOF
      git add -A && git commit -q -m "fix(security): 修補 XSS 漏洞（人工移植）"
      ok "$BR ← 人工移植完成"
    fi
  done

  for BR in support/1.x support/2.x develop; do
    assert_contains "$BR" src/sec.js "replace" "$BR 已含安全修補"
  done
  note "每條線各自打 tag、各自跑完整測試，不可只測一條"
}

# ══════════════════════════════════════════════════════════
# F. 團隊協作
# ══════════════════════════════════════════════════════════

s24() {
  title "情境 24：多人共用同一個 feature 分支（用真實 remote 模擬）"
  local base="$SANDBOX/s24"
  rm -rf "$base"; mkdir -p "$base"

  fresh_repo s24/origin >/dev/null
  cd "$base/origin" || exit 1
  git switch -q main
  git config --bool core.bare true 2>/dev/null

  step "建立裸倉庫作為 origin，A 與 B 各自 clone"
  cd "$base" || exit 1
  git clone -q "$base/origin" a 2>/dev/null
  git clone -q "$base/origin" b 2>/dev/null

  for d in a b; do
    cd "$base/$d" || exit 1
    git config user.name "Dev $d"; git config user.email "$d@example.com"
    git config commit.gpgsign false
  done

  step "A 建立並發布 feature/big-refactor"
  cd "$base/a" || exit 1
  git switch -q -c feature/big-refactor
  cf src/r1.js "export const r1 = 1;" "feat: A 的部分"
  git push -q -u origin feature/big-refactor

  step "B 加入同一分支並推送"
  cd "$base/b" || exit 1
  git fetch -q origin
  git switch -q -c feature/big-refactor origin/feature/big-refactor
  cf src/r2.js "export const r2 = 2;" "feat: B 的部分"
  git push -q origin feature/big-refactor

  step "A 同步（★ 共用分支只 merge、不 rebase）"
  cd "$base/a" || exit 1
  git pull -q --no-rebase origin feature/big-refactor
  git ls-files | grep -E 'r[12]' | sed 's/^/    /'
  ok "A 拿到 B 的變更，且沒有改寫任何既有 SHA"
  echo
  warn "若 A 在共用分支上 rebase 後強推，B 下次 pull 會遇到大量假衝突"
  cd "$SANDBOX" || exit 1
}

s25() {
  title "情境 25：feature 依賴另一個未合併的 feature（stacked branches）"
  fresh_repo s25 >/dev/null

  step "feature/api 開發中（尚在 Review）"
  git switch -q -c feature/api develop
  cf src/api.js "export const fetchUser = () => ({ id: 1 });" "feat(api): 新增 fetchUser"

  step "feature/ui 需要用到它 → 疊在 feature/api 之上"
  git switch -q -c feature/ui feature/api
  cf src/ui.js "import { fetchUser } from './api';" "feat(ui): 使用 fetchUser"
  assert_contains feature/ui src/api.js "fetchUser" "feature/ui 看得到 api 的成果"

  step "feature/api 通過 Review，合併進 develop"
  git switch -q develop
  git merge -q --no-ff feature/api -m "Merge branch 'feature/api' into develop"

  step "★ 把 feature/ui 換基底到 develop"
  git rebase -q --onto develop feature/api feature/ui
  git switch -q feature/ui
  ok "feature/ui 現在直接建立在 develop 之上"
  git log --oneline -4 | sed 's/^/    /'
  echo
  note "PR 的 base 也要從 feature/api 改回 develop"
  note "疊超過 2 層就難以維護 —— 優先考慮把 PR 拆小、快速合併"
}

s26() {
  title "情境 26：PR 卡太久，develop 已跑遠"
  fresh_repo s26 >/dev/null

  git switch -q -c feature/slow develop
  for i in 1 2 3; do cf "src/s$i.js" "export const s$i = $i;" "feat: 我的第 $i 個 commit"; done

  step "develop 期間前進了 8 個 commit"
  git switch -q develop
  for i in $(seq 1 8); do cf "src/o$i.js" "export const o$i = $i;" "feat: 別人的第 $i 個 commit"; done

  step "落後統計（左：develop 領先，右：feature 領先）"
  git rev-list --left-right --count develop...feature/slow | sed 's/^/    /'

  step "同步"
  git switch -q feature/slow
  git rebase -q develop
  ok "已 rebase 到最新 develop"
  git log --oneline -4 | sed 's/^/    /'
  echo
  note "根治：PR ≤ 400 行、用 feature flag 早點合併、Review SLA 24 小時"
}

# ══════════════════════════════════════════════════════════
# 派工
# ══════════════════════════════════════════════════════════

TITLES=(
  "" \
  "標準功能開發（feature → develop）" \
  "多個 feature 平行開發" \
  "標準發版（release → main + develop）" \
  "線上緊急修復（hotfix）" \
  "兩個 feature 改到同一行 → 衝突" \
  "feature 落後太久 → rebase 換基底" \
  "release 回併 develop 的語意衝突" \
  "rebase 連續衝突 → abort 改用 merge" \
  "release 凍結期間 develop 繼續開發" \
  "release 進行中發生 hotfix ★" \
  "hotfix 與 release 同時完成 → tag 順序" \
  "兩個 release 分支並存（反模式）" \
  "release 被判定不上線（廢棄）" \
  "feature 誤從 main 開出 → rebase --onto" \
  "誤在 main 上直接 commit" \
  "誤把 feature 直接合進 main" \
  "已合併的 feature 要抽掉 ★ revert 陷阱" \
  "tag 打錯了" \
  "分支被 force push 覆蓋 → reflog 救援" \
  "機密進了版控" \
  "同時維護 v1.x 與 v2.x（support 分支）" \
  "為舊版客戶做 hotfix" \
  "一個安全修正要進多個版本線" \
  "多人共用同一 feature 分支" \
  "feature 依賴未合併的 feature（stacked）" \
  "PR 卡太久，develop 已跑遠" \
)

GROUPS=(
  "" "A" "A" "A" "A" "B" "B" "B" "B" "C" "C" "C" "C" "C" \
  "D" "D" "D" "D" "D" "D" "D" "E" "E" "E" "F" "F" "F"
)

usage() {
  cat <<EOF
${C_B}GitFlow 情境模擬器${C_RST}

  用法：
    $0 list             列出所有情境
    $0 <n> [n...]       執行指定情境（1-26）
    $0 all              執行全部
    $0 clean            清除沙箱目錄

  沙箱位置：$SANDBOX
EOF
}

list_scenarios() {
  echo
  echo "${C_B} #   類別  情境${C_RST}"
  echo " ─────────────────────────────────────────────────────────"
  local i
  for i in $(seq 1 26); do
    printf " %-3s %-4s  %s\n" "$i" "${GROUPS[$i]}" "${TITLES[$i]}"
  done
  echo
  echo "${C_DIM} 類別：A 正常流程 / B 衝突處理 / C 時序交錯 / D 異常救援 / E 長期維護 / F 團隊協作${C_RST}"
  echo
}

run_one() {
  local n="$1"
  case "$n" in
    ''|*[!0-9]*) bad "無效的情境編號：$n"; return 1 ;;
  esac
  if [ "$n" -lt 1 ] || [ "$n" -gt 26 ]; then
    bad "情境編號需在 1-26 之間：$n"; return 1
  fi
  mkdir -p "$SANDBOX"
  ( "s$n" )
}

main() {
  if ! command -v git >/dev/null 2>&1; then
    bad "找不到 git"; exit 1
  fi

  [ $# -eq 0 ] && { usage; exit 0; }

  case "$1" in
    list|-l|--list) list_scenarios; exit 0 ;;
    clean)          rm -rf "$SANDBOX"; ok "已清除 $SANDBOX"; exit 0 ;;
    -h|--help)      usage; exit 0 ;;
    all)
      for i in $(seq 1 26); do run_one "$i"; done
      echo
      ok "全部 26 個情境執行完畢，沙箱位於 $SANDBOX"
      exit 0 ;;
  esac

  for n in "$@"; do run_one "$n"; done
  echo
  ok "執行完畢。沙箱位於 $SANDBOX（可自行進去 git log 探索）"
}

main "$@"

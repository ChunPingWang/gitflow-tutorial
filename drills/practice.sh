#!/usr/bin/env bash
#
# Git 互動演練場 —— 給初學者的動手練習
# ------------------------------------------------------------
# 與 scenarios/simulate.sh 的差別：
#   simulate.sh  = 「看」  腳本自己跑完，你看結果學觀念
#   practice.sh  = 「做」  幫你佈置好情境，指令由你自己下，再由它驗收
#
#   ./drills/practice.sh list          列出 12 個練習
#   ./drills/practice.sh start 5       佈置第 5 題並顯示任務
#   ./drills/practice.sh check 5       驗收你的成果
#   ./drills/practice.sh hint 5        看提示（不含答案）
#   ./drills/practice.sh solve 5       看完整解答（會直接幫你做完）
#   ./drills/practice.sh reset 5       重置這一題
#   ./drills/practice.sh clean         清除所有練習
#
# 相容 bash 3.2（macOS 內建版本）
# ------------------------------------------------------------

set -u
# 註：刻意不開 pipefail —— 「git log | grep -q」中 grep 提早結束會讓 git 收到
#     SIGPIPE（退出碼 141），開了 pipefail 會把成功的比對誤判成失敗。

ROOT="${GITFLOW_DRILLS:-/tmp/gitflow-drills}"
TOTAL=12

if [ -t 1 ]; then
  C_RST=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
  C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_C=$'\033[36m'; C_M=$'\033[35m'
else
  C_RST=''; C_B=''; C_DIM=''; C_R=''; C_G=''; C_Y=''; C_C=''; C_M=''
fi

box() {
  echo
  echo "${C_C}┌────────────────────────────────────────────────────────────┐${C_RST}"
  printf "${C_C}│${C_RST} ${C_B}%-58s${C_RST} ${C_C}│${C_RST}\n" "$1"
  echo "${C_C}└────────────────────────────────────────────────────────────┘${C_RST}"
}
task()  { echo; echo "${C_B}📋 任務${C_RST}"; echo "$1"; }
tip()   { echo; echo "${C_M}💡 建議${C_RST}"; echo "$1"; }
learn() { echo; echo "${C_Y}🎓 學習重點${C_RST}"; echo "$1"; }
pass()  { echo "  ${C_G}✔${C_RST} $1"; }
fail()  { echo "  ${C_R}✘${C_RST} $1"; FAILED=$((FAILED+1)); }
info()  { echo "${C_DIM}$1${C_RST}"; }
where() { echo; echo "${C_DIM}📂 練習目錄：$1${C_RST}"; echo "${C_DIM}   cd $1${C_RST}"; }

dir_of() { echo "$ROOT/d$1"; }

# 建立乾淨的 repo 骨架
init_repo() {
  local d="$1"
  rm -rf "$d"; mkdir -p "$d"; cd "$d" || exit 1
  git init -q -b main
  git config user.name  "Learner"
  git config user.email "learner@example.com"
  git config commit.gpgsign false
  git config merge.conflictstyle zdiff3
  git config advice.detachedHead false
}
qc() { git add -A && git commit -q -m "$1"; }

# ══════════════════════════════════════════════════════════
# 1. 第一個 commit
# ══════════════════════════════════════════════════════════
setup_1() {
  local d; d=$(dir_of 1); init_repo "$d"
  echo "Hello, Git!" > hello.txt
  echo "這個檔案不該進版控" > debug.log
}
task_1() {
  task "1. 把 ${C_B}hello.txt${C_RST} 加入版控並提交，commit 訊息為：
     ${C_C}feat: 新增問候檔案${C_RST}
  2. 讓 ${C_B}debug.log${C_RST} ${C_B}不要${C_RST}進入版控（建立 .gitignore），
     並把 .gitignore 一起提交，訊息為：
     ${C_C}chore: 加入 gitignore${C_RST}"
  tip "先用 ${C_C}git status${C_RST} 看清楚目前有哪些檔案未被追蹤。
  status 是你最該養成習慣的指令 —— 每個動作前後都看一次。"
}
hint_1() {
  info "  git status
  git add hello.txt
  git commit -m \"...\"
  echo 'debug.log' > .gitignore     # 或 *.log
  git add .gitignore && git commit -m \"...\""
}
check_1() {
  git log --oneline >/dev/null 2>&1 && pass "已有 commit" || { fail "還沒有任何 commit"; return; }
  git ls-files --error-unmatch hello.txt >/dev/null 2>&1 \
    && pass "hello.txt 已納入版控" || fail "hello.txt 尚未納入版控"
  git ls-files --error-unmatch debug.log >/dev/null 2>&1 \
    && fail "debug.log 不該進版控（請用 .gitignore 排除）" || pass "debug.log 未進版控"
  [ -f .gitignore ] && git ls-files --error-unmatch .gitignore >/dev/null 2>&1 \
    && pass ".gitignore 已建立並提交" || fail ".gitignore 尚未建立或尚未提交"
  git log --format=%s | grep -q '^feat: 新增問候檔案$' \
    && pass "commit 訊息符合要求" || fail "找不到訊息為 'feat: 新增問候檔案' 的 commit"
  learn "Git 只管「被追蹤的檔案」。.gitignore 對已追蹤的檔案無效 ——
  那種情況要先 ${C_C}git rm --cached <file>${C_RST} 把它移出索引。"
}
solve_1() {
  git add hello.txt && git commit -q -m "feat: 新增問候檔案"
  echo "*.log" > .gitignore
  git add .gitignore && git commit -q -m "chore: 加入 gitignore"
}

# ══════════════════════════════════════════════════════════
# 2. 三大區域：工作目錄 / 暫存區 / 版本庫
# ══════════════════════════════════════════════════════════
setup_2() {
  local d; d=$(dir_of 2); init_repo "$d"
  echo "價格 = 100" > price.txt
  echo "數量 = 5"   > qty.txt
  qc "chore: 初始化"
  echo "價格 = 200" > price.txt      # 想保留的修改
  echo "數量 = 999" > qty.txt        # 誤改，想丟掉
}
task_2() {
  task "目前兩個檔案都被改過了：
    · ${C_B}price.txt${C_RST}  100 → 200   ${C_G}（正確的修改，要保留並 stage）${C_RST}
    · ${C_B}qty.txt${C_RST}    5 → 999     ${C_R}（誤改，要丟棄）${C_RST}

  請做到：
    1. 把 price.txt 放進${C_B}暫存區${C_RST}（但${C_B}先不要 commit${C_RST}）
    2. 把 qty.txt 的修改${C_B}完全丟棄${C_RST}，回到 100/5 的原狀"
  tip "分清楚兩個 diff：
    ${C_C}git diff${C_RST}          工作目錄 vs 暫存區（還沒 add 的）
    ${C_C}git diff --staged${C_RST}  暫存區 vs HEAD（這次 commit 會提交什麼）"
}
hint_2() {
  info "  git status
  git add price.txt
  git restore qty.txt          # 舊寫法：git checkout -- qty.txt
  git status                   # 再確認一次"
}
check_2() {
  git diff --staged --name-only | grep -qx "price.txt" \
    && pass "price.txt 已在暫存區" || fail "price.txt 尚未加入暫存區"
  grep -q "200" price.txt 2>/dev/null \
    && pass "price.txt 的修改保留著" || fail "price.txt 的修改不見了"
  grep -q "數量 = 5$" qty.txt 2>/dev/null \
    && pass "qty.txt 已還原" || fail "qty.txt 尚未還原（現在是：$(cat qty.txt 2>/dev/null)）"
  [ -z "$(git log --oneline HEAD~1..HEAD 2>/dev/null | grep -v 初始化)" ] \
    && pass "尚未 commit（符合題目要求）" || true
  learn "restore 有兩種用法，差一個參數天差地遠：
    ${C_C}git restore <file>${C_RST}            丟棄工作目錄的修改（${C_R}不可復原${C_RST}）
    ${C_C}git restore --staged <file>${C_RST}   只把檔案移出暫存區（修改還在）"
}
solve_2() { git add price.txt; git restore qty.txt; }

# ══════════════════════════════════════════════════════════
# 3. 分支操作
# ══════════════════════════════════════════════════════════
setup_3() {
  local d; d=$(dir_of 3); init_repo "$d"
  echo "# App" > README.md
  qc "chore: 初始化專案"
  git tag -a v1.0.0 -m "Release 1.0.0"
}
task_3() {
  task "目前只有 main 分支。請建立 GitFlow 的分支骨架：
    1. 從 main 建立 ${C_B}develop${C_RST} 分支並切換過去
    2. 從 develop 建立 ${C_B}feature/greeting${C_RST} 並切換過去
    3. 在 feature/greeting 上新增檔案 ${C_B}greeting.txt${C_RST}（內容任意）並 commit
    4. 最後停留在 feature/greeting 上"
  tip "「建立 + 切換」一次完成：${C_C}git switch -c <分支名>${C_RST}
  想確認自己在哪：${C_C}git branch${C_RST}（有 * 的那個）或 ${C_C}git status${C_RST} 第一行。"
}
hint_3() {
  info "  git switch -c develop
  git switch -c feature/greeting
  echo hi > greeting.txt
  git add greeting.txt && git commit -m \"feat: 新增問候\"
  git log --oneline --graph --all"
}
check_3() {
  git show-ref -q --verify refs/heads/develop \
    && pass "develop 分支存在" || fail "找不到 develop 分支"
  git show-ref -q --verify refs/heads/feature/greeting \
    && pass "feature/greeting 分支存在" || fail "找不到 feature/greeting 分支"
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature/greeting" ] \
    && pass "目前位於 feature/greeting" || fail "目前在 $(git rev-parse --abbrev-ref HEAD)，應在 feature/greeting"
  git show feature/greeting:greeting.txt >/dev/null 2>&1 \
    && pass "greeting.txt 已提交" || fail "greeting.txt 尚未提交"
  if git merge-base --is-ancestor develop feature/greeting 2>/dev/null; then
    pass "feature/greeting 建立在 develop 之上"
  else
    fail "feature/greeting 的基底不是 develop（GitFlow 規定 feature 必須從 develop 開）"
  fi
  learn "分支只是一個 41 bytes 的檔案，裡面存著一個 commit SHA。
  ${C_C}cat .git/refs/heads/develop${C_RST} 自己看看 —— 所以開分支幾乎不花成本。"
}
solve_3() {
  git switch -q -c develop
  git switch -q -c feature/greeting
  echo "Hello" > greeting.txt
  git add greeting.txt && git commit -q -m "feat: 新增問候"
}

# ══════════════════════════════════════════════════════════
# 4. fast-forward vs --no-ff
# ══════════════════════════════════════════════════════════
setup_4() {
  local d; d=$(dir_of 4); init_repo "$d"
  echo "# App" > README.md; qc "chore: 初始化專案"
  git switch -q -c develop
  git switch -q -c feature/login
  echo "login form"  > login.js; qc "feat(auth): 登入表單"
  echo "login api"  >> login.js; qc "feat(auth): 串接 API"
  git switch -q develop
}
task_4() {
  task "你現在在 develop 上，feature/login 有 2 個 commit。

  請用 ${C_B}--no-ff${C_RST} 的方式把 feature/login 合併進 develop，
  合併訊息為：${C_C}Merge branch 'feature/login' into develop${C_RST}

  合併後刪除 feature/login 分支。"
  tip "develop 從分家後沒有新 commit，直接 merge 會發生 ${C_B}fast-forward${C_RST} ——
  指標直接前移，${C_R}看不出這 2 個 commit 屬於同一個功能${C_RST}。
  GitFlow 一律用 --no-ff，就是為了保住這個資訊。"
}
hint_4() {
  info "  git merge --no-ff feature/login -m \"Merge branch 'feature/login' into develop\"
  git branch -d feature/login
  git log --oneline --graph --all"
}
check_4() {
  [ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ] \
    && pass "位於 develop" || fail "應停留在 develop"
  local parents; parents=$(git rev-list --parents -n1 HEAD | wc -w | tr -d ' ')
  if [ "$parents" -ge 3 ]; then
    pass "HEAD 是合併節點（有兩個父 commit）→ --no-ff 成功"
  else
    fail "HEAD 不是合併節點 —— 你可能做成了 fast-forward（少了 --no-ff）"
  fi
  git show develop:login.js 2>/dev/null | grep -q "api" \
    && pass "功能已併入 develop" || fail "develop 上找不到 feature 的內容"
  git show-ref -q --verify refs/heads/feature/login \
    && fail "feature/login 尚未刪除" || pass "feature/login 已刪除"
  learn "合併後 ${C_C}git log --oneline --graph${C_RST} 看得到菱形結構，
  代表這裡曾有一個功能分支。要整批撤掉這個功能時，
  ${C_C}git revert -m 1 <merge-sha>${C_RST} 一行就能做到。"
}
solve_4() {
  git merge -q --no-ff feature/login -m "Merge branch 'feature/login' into develop"
  git branch -q -d feature/login
}

# ══════════════════════════════════════════════════════════
# 5. ★ 製造並解決合併衝突
# ══════════════════════════════════════════════════════════
setup_5() {
  local d; d=$(dir_of 5); init_repo "$d"
  cat > pricing.js <<'EOF'
export const config = {
  currency: 'TWD',
  discount: 0.1,
  freeShipping: 1000,
};
EOF
  qc "chore: 初始化定價設定"
  git switch -q -c develop

  git switch -q -c feature/discount
  cat > pricing.js <<'EOF'
export const config = {
  currency: 'TWD',
  discount: 0.2,
  freeShipping: 1000,
};
EOF
  qc "feat(pricing): 折扣提高到 2 成"

  git switch -q develop
  cat > pricing.js <<'EOF'
export const config = {
  currency: 'TWD',
  discount: 0.1,
  freeShipping: 500,
};
EOF
  qc "feat(pricing): 免運門檻降到 500"
}
task_5() {
  task "${C_B}develop${C_RST} 與 ${C_B}feature/discount${C_RST} 改到了同一個檔案的相鄰行：
    · develop           freeShipping: 1000 → ${C_C}500${C_RST}
    · feature/discount  discount: 0.1 → ${C_C}0.2${C_RST}

  請在 develop 上執行 ${C_B}--no-ff${C_RST} 合併，解決衝突，
  最終 pricing.js 必須${C_B}同時保留兩邊的修改${C_RST}：
    ${C_C}discount: 0.2${C_RST}  且  ${C_C}freeShipping: 500${C_RST}"
  tip "解衝突的順序永遠是這五步：
    ${C_C}1. git status${C_RST}                      看哪些檔案卡住（Unmerged paths）
    ${C_C}2. 編輯檔案${C_RST}                        刪掉 <<<<<<< ======= >>>>>>> 三種標記
    ${C_C}3. git add <file>${C_RST}                  標記為已解決
    ${C_C}4. git status${C_RST}                      確認沒有遺漏
    ${C_C}5. git commit${C_RST}                      完成合併（訊息已預填）

  ${C_R}做錯了不用怕${C_RST}：${C_C}git merge --abort${C_RST} 隨時可以回到合併前，什麼都沒發生。"
}
hint_5() {
  info "  git merge --no-ff feature/discount
  # → CONFLICT (content): Merge conflict in pricing.js
  git status
  cat pricing.js               # 看衝突標記
  # 手動編輯成：discount: 0.2 且 freeShipping: 500
  git add pricing.js
  git commit --no-edit"
}
check_5() {
  if [ -f .git/MERGE_HEAD ]; then
    fail "合併尚未完成（還在衝突處理中）—— 解完後別忘了 git add + git commit"
  fi
  grep -qE '^(<<<<<<<|=======|>>>>>>>|\|\|\|\|\|\|\|)' pricing.js 2>/dev/null \
    && fail "pricing.js 裡還留著衝突標記！請刪乾淨" \
    || pass "沒有殘留的衝突標記"
  grep -q "discount: 0.2" pricing.js 2>/dev/null \
    && pass "保留了 feature 的修改（discount: 0.2）" \
    || fail "discount 應為 0.2（feature 那一邊的修改）"
  grep -q "freeShipping: 500" pricing.js 2>/dev/null \
    && pass "保留了 develop 的修改（freeShipping: 500）" \
    || fail "freeShipping 應為 500（develop 這一邊的修改）"
  local parents; parents=$(git rev-list --parents -n1 HEAD 2>/dev/null | wc -w | tr -d ' ')
  [ "$parents" -ge 3 ] && pass "HEAD 是合併節點" || fail "HEAD 不是合併節點，合併沒有完成"
  learn "衝突${C_B}不是錯誤${C_RST}，是 Git 在說「這兩個改動我不敢替你決定」。
  它只比對文字，不理解語意 —— 所以解完${C_B}一定要跑測試${C_RST}。
  想看得更清楚：${C_C}git config --global merge.conflictstyle zdiff3${C_RST}
  會多顯示 ${C_C}|||||||${C_RST} 共同祖先段，讓你知道兩邊各自改了什麼。"
}
solve_5() {
  git merge --no-ff feature/discount >/dev/null 2>&1
  cat > pricing.js <<'EOF'
export const config = {
  currency: 'TWD',
  discount: 0.2,
  freeShipping: 500,
};
EOF
  git add pricing.js
  git commit -q --no-edit
}

# ══════════════════════════════════════════════════════════
# 6. 標籤
# ══════════════════════════════════════════════════════════
setup_6() {
  local d; d=$(dir_of 6); init_repo "$d"
  echo "v0.9" > app.txt; qc "feat: 初版功能"
  echo "v0.9.1" > app.txt; qc "fix: 修正錯字"
  echo "v1.0" > app.txt; qc "feat: 正式版功能"
}
task_6() {
  info "  目前 main 上有 3 個 commit："
  git log --oneline | sed 's/^/    /'
  task "1. 為${C_B}最新的 commit${C_RST} 打上 ${C_B}annotated tag${C_RST}：
     名稱 ${C_C}v1.0.0${C_RST}，訊息 ${C_C}Release 1.0.0${C_RST}
  2. 為${C_B}最舊的那個 commit${C_RST}（feat: 初版功能）補打 annotated tag：
     名稱 ${C_C}v0.9.0${C_RST}，訊息 ${C_C}Release 0.9.0${C_RST}"
  tip "兩種 tag 差很多，正式發版${C_B}一定要用 annotated${C_RST}：
    ${C_C}git tag v1.0.0${C_RST}                    lightweight，只是一個指標
    ${C_C}git tag -a v1.0.0 -m \"訊息\"${C_RST}       annotated，是一個完整物件
                                        （含作者、日期、訊息，可簽章）"
}
hint_6() {
  info "  git tag -a v1.0.0 -m \"Release 1.0.0\"
  git log --oneline              # 找出最舊 commit 的 SHA
  git tag -a v0.9.0 <那個SHA> -m \"Release 0.9.0\"
  git tag -l -n1
  git show v1.0.0"
}
check_6() {
  if [ "$(git cat-file -t v1.0.0 2>/dev/null)" = "tag" ]; then
    pass "v1.0.0 是 annotated tag"
  else
    [ -n "$(git tag -l v1.0.0)" ] \
      && fail "v1.0.0 是 lightweight tag，請改用 -a 重打" \
      || fail "找不到 v1.0.0"
  fi
  [ "$(git rev-list -n1 v1.0.0 2>/dev/null)" = "$(git rev-parse main)" ] \
    && pass "v1.0.0 指向最新的 commit" || fail "v1.0.0 沒有指向最新的 commit"
  if [ "$(git cat-file -t v0.9.0 2>/dev/null)" = "tag" ]; then
    pass "v0.9.0 是 annotated tag"
  else
    [ -n "$(git tag -l v0.9.0)" ] \
      && fail "v0.9.0 是 lightweight tag，請改用 -a 重打" \
      || fail "找不到 v0.9.0"
  fi
  local oldest; oldest=$(git rev-list --max-parents=0 HEAD)
  [ "$(git rev-list -n1 v0.9.0 2>/dev/null)" = "$oldest" ] \
    && pass "v0.9.0 指向最舊的 commit" || fail "v0.9.0 沒有指向最舊的 commit"
  learn "tag 是${B:-}${C_B}公開契約${C_RST}：CI/CD、套件註冊表、客戶下載連結都可能綁著它。
  已 push 的 tag 能不動就不動；真要改，必須公告全隊
  ${C_C}git fetch --tags --force${C_RST}。
  tag 不會自動推送：${C_C}git push origin v1.0.0${C_RST} 或 ${C_C}--follow-tags${C_RST}。"
}
solve_6() {
  git tag -a v1.0.0 -m "Release 1.0.0"
  git tag -a v0.9.0 "$(git rev-list --max-parents=0 HEAD)" -m "Release 0.9.0"
}

# ══════════════════════════════════════════════════════════
# 7. 撤銷三兄弟：restore / reset / revert
# ══════════════════════════════════════════════════════════
setup_7() {
  local d; d=$(dir_of 7); init_repo "$d"
  echo "正式內容" > doc.txt
  echo "設定 = A"  > conf.txt
  qc "chore: 初始化"
  echo "重要功能" > feature.txt; qc "feat: 重要功能"
  echo "壞掉的東西" > broken.txt; qc "feat: 這個 commit 是壞的"
  echo "亂改的內容" > doc.txt          # 未 commit 的誤改
  echo "設定 = B"  > conf.txt
  git add conf.txt                     # 已 stage，但不想 commit
}
task_7() {
  info "  目前狀態："
  git status --short | sed 's/^/    /'
  git log --oneline | sed 's/^/    /'
  task "三種撤銷各做一次：
    1. ${C_B}doc.txt${C_RST} 被亂改（未 stage）→ 丟棄修改，回到「正式內容」
    2. ${C_B}conf.txt${C_RST} 已 stage 但不想提交 → 移出暫存區（${C_B}修改要保留${C_RST}）
    3. 最新的 commit ${C_B}'feat: 這個 commit 是壞的'${C_RST} 已經推給別人了
       → 用${C_B}產生反向 commit${C_RST} 的方式抵銷它（${C_R}不可改寫歷史${C_RST}）"
  tip "選哪一個，只問一句話：${C_B}這個 commit 推出去了嗎？${C_RST}
    ${C_G}沒推${C_RST} → ${C_C}git reset${C_RST}   直接改寫歷史，乾淨
    ${C_R}推了${C_RST} → ${C_C}git revert${C_RST}  產生反向 commit，別人不會爆炸"
}
hint_7() {
  info "  git restore doc.txt              # 1
  git restore --staged conf.txt    # 2
  git revert HEAD --no-edit        # 3（不是 reset！）
  git log --oneline"
}
check_7() {
  grep -q "正式內容" doc.txt 2>/dev/null \
    && pass "doc.txt 已還原" || fail "doc.txt 尚未還原"
  if git diff --staged --name-only | grep -qx "conf.txt"; then
    fail "conf.txt 還在暫存區（請用 git restore --staged）"
  else
    pass "conf.txt 已移出暫存區"
    grep -q "設定 = B" conf.txt 2>/dev/null \
      && pass "conf.txt 的修改仍保留（沒有誤用 restore 丟掉）" \
      || fail "conf.txt 的修改被丟掉了 —— --staged 參數不能省"
  fi
  if git log --format=%s | grep -q '^Revert "feat: 這個 commit 是壞的"'; then
    pass "已用 revert 抵銷壞 commit"
  else
    if git log --format=%s | grep -q '這個 commit 是壞的'; then
      fail "尚未 revert 那個壞 commit"
    else
      fail "壞 commit 從歷史中消失了 —— 你用了 reset，但題目說它已經推出去了"
    fi
  fi
  [ ! -f broken.txt ] && pass "broken.txt 的內容已被抵銷" || fail "broken.txt 還在，revert 沒有生效"
  learn "revert 之後歷史會多兩個 commit（原本的 + 反向的），這是正確的代價。
  ${C_C}git log${C_RST} 看得到「做了什麼、又為什麼收回」，對團隊反而更誠實。"
}
solve_7() {
  git restore doc.txt
  git restore --staged conf.txt
  git revert --no-edit HEAD >/dev/null
}

# ══════════════════════════════════════════════════════════
# 8. stash
# ══════════════════════════════════════════════════════════
setup_8() {
  local d; d=$(dir_of 8); init_repo "$d"
  echo "穩定版" > app.txt; qc "chore: 初始化"
  git switch -q -c develop
  echo "做到一半的新功能..." > wip.txt
  echo "穩定版 + 改到一半" > app.txt
}
task_8() {
  info "  你在 develop 上，手邊有做到一半的工作："
  git status --short | sed 's/^/    /'
  task "此時線上出事，必須立刻切到 main 修 bug。但工作做到一半不能 commit。

    1. 用 ${C_B}stash${C_RST} 把目前的工作收起來（${C_B}含未追蹤的 wip.txt${C_RST}）
    2. 切到 ${C_B}main${C_RST}，把 app.txt 改成 ${C_C}穩定版 + 緊急修復${C_RST}，
       commit 訊息 ${C_C}fix: 緊急修復${C_RST}
    3. 切回 ${C_B}develop${C_RST}，把剛才收起來的工作取回來
    4. 最終 develop 上要同時看得到 wip.txt 和改到一半的 app.txt"
  tip "${C_R}陷阱${C_RST}：預設的 ${C_C}git stash${C_RST} ${C_B}不會${C_RST}收未追蹤的檔案（wip.txt 會被留下）。
  要一起收必須加 ${C_C}-u${C_RST}（--include-untracked）。"
}
hint_8() {
  info "  git stash -u -m \"新功能做到一半\"
  git status                    # 應該乾淨了
  git switch main
  echo '穩定版 + 緊急修復' > app.txt
  git commit -am \"fix: 緊急修復\"
  git switch develop
  git stash pop
  git stash list                # 應為空"
}
check_8() {
  [ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ] \
    && pass "已切回 develop" || fail "應停留在 develop"
  git log --format=%s main 2>/dev/null | grep -q '^fix: 緊急修復$' \
    && pass "main 上有緊急修復的 commit" || fail "main 上找不到 'fix: 緊急修復'"
  git show main:app.txt 2>/dev/null | grep -q "緊急修復" \
    && pass "main 的內容已修復" || fail "main 的 app.txt 沒有被修復"
  [ -f wip.txt ] && pass "wip.txt 已取回（-u 有加對）" \
    || fail "wip.txt 不見了 —— stash 時少了 -u，未追蹤檔案沒被收進去"
  grep -q "改到一半" app.txt 2>/dev/null \
    && pass "develop 上做到一半的修改已取回" || fail "develop 上的修改沒有取回"
  [ -z "$(git stash list)" ] \
    && pass "stash 堆疊已清空（用了 pop）" \
    || info "  ${C_Y}⚠${C_RST} stash 堆疊還有東西（用 apply 不會清除，pop 才會）"
  learn "${C_C}pop${C_RST} = apply + drop（取回並移除）
  ${C_C}apply${C_RST} = 只取回，保留在堆疊裡（要套用到多個分支時用它）
  stash 是一個堆疊，${C_C}git stash list${C_RST} 常看一下，別讓東西沉在裡面被遺忘。"
}
solve_8() {
  git stash -u -m "新功能做到一半" >/dev/null
  git switch -q main
  echo "穩定版 + 緊急修復" > app.txt
  git commit -q -am "fix: 緊急修復"
  git switch -q develop
  git stash pop >/dev/null
}

# ══════════════════════════════════════════════════════════
# 9. cherry-pick
# ══════════════════════════════════════════════════════════
setup_9() {
  local d; d=$(dir_of 9); init_repo "$d"
  echo "app v1" > app.txt; qc "chore: 初始化"
  git tag -a v1.0.0 -m "Release 1.0.0"
  git switch -q -c develop
  echo "開發中的新功能" > next.txt; qc "feat: 下一版的功能"
  git switch -q main
  echo "security patch" > security.txt; qc "fix(security): 修補漏洞"
  echo "readme" > NOTES.md; qc "docs: 補充說明"
  git switch -q develop
}
task_9() {
  info "  main 上有 2 個 commit 是 develop 沒有的："
  git log --oneline develop..main | sed 's/^/    /'
  task "你在 develop 上。只有 ${C_B}fix(security): 修補漏洞${C_RST} 這一個 commit
  需要帶進 develop，${C_B}docs 那個不要${C_RST}。

  請用 ${C_C}cherry-pick${C_RST} 把它挑過來。"
  tip "cherry-pick 適合「只要某一個 commit」的情境。
  若整個分支都要，用 merge；若要換基底，用 rebase。
  挑過來的 commit ${C_B}SHA 會不一樣${C_RST}（父 commit 變了），內容相同。"
}
hint_9() {
  info "  git log --oneline develop..main       # 找出那個 commit 的 SHA
  git cherry-pick <SHA>
  git log --oneline -3"
}
check_9() {
  [ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ] \
    && pass "位於 develop" || fail "應停留在 develop"
  git show develop:security.txt >/dev/null 2>&1 \
    && pass "security.txt 已進入 develop" || fail "develop 上找不到 security.txt"
  git show develop:NOTES.md >/dev/null 2>&1 \
    && fail "NOTES.md 也被帶進來了 —— 題目只要 security 那一個 commit" \
    || pass "沒有多帶 docs 的 commit"
  local dsha msha
  dsha=$(git log --format='%H %s' develop | grep '修補漏洞' | head -1 | cut -d' ' -f1)
  msha=$(git log --format='%H %s' main    | grep '修補漏洞' | head -1 | cut -d' ' -f1)
  if [ -n "$dsha" ] && [ "$dsha" != "$msha" ]; then
    pass "cherry-pick 產生了新的 SHA（${dsha:0:7} ≠ ${msha:0:7}）"
  elif [ -n "$dsha" ]; then
    info "  ${C_Y}⚠${C_RST} SHA 相同，你可能是用 merge 而非 cherry-pick"
  fi
  learn "GitFlow 的 hotfix 正規做法是「合進 main + 合進 develop」。
  但當你只要其中${C_B}一個${C_RST} commit（例如多版本並行維護時），
  cherry-pick 更精準。它也是把修正移植到 ${C_C}support/*${C_RST} 舊版分支的主力工具。"
}
solve_9() {
  local sha; sha=$(git log --format='%H %s' main | grep '修補漏洞' | head -1 | cut -d' ' -f1)
  git cherry-pick "$sha" >/dev/null 2>&1
}

# ══════════════════════════════════════════════════════════
# 10. rebase 換基底
# ══════════════════════════════════════════════════════════
setup_10() {
  local d; d=$(dir_of 10); init_repo "$d"
  echo "base" > base.txt; qc "chore: 初始化"
  git switch -q -c develop
  git switch -q -c feature/report
  echo "r1" > r1.txt; qc "feat(report): 報表骨架"
  echo "r2" > r2.txt; qc "feat(report): 加入圖表"
  git switch -q develop
  for i in 1 2 3; do echo "d$i" > "d$i.txt"; qc "feat: develop 新增功能 $i"; done
  git switch -q feature/report
}
task_10() {
  info "  你在 feature/report（2 個 commit），期間 develop 前進了 3 個 commit："
  git log --oneline --graph --all | head -10 | sed 's/^/    /'
  task "請把 feature/report ${C_B}rebase 到最新的 develop${C_RST} 之上，
  讓歷史變成一條直線，且你的 2 個 commit 排在 develop 的 3 個 commit 之後。"
  tip "先確認落後多少：
    ${C_C}git rev-list --left-right --count develop...feature/report${C_RST}
    → 左邊是 develop 領先數，右邊是你領先數

  ${C_R}黃金法則${C_RST}：只 rebase ${C_B}自己一個人用${C_RST}的分支。
  rebase 會產生新 SHA，別人基於舊 SHA 的工作會全部對不上。"
}
hint_10() {
  info "  git rebase develop
  git log --oneline --graph --all
  # 若有衝突：解衝突 → git add <file> → git rebase --continue
  # 想放棄：git rebase --abort"
}
check_10() {
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature/report" ] \
    && pass "位於 feature/report" || fail "應停留在 feature/report"
  if [ "$(git merge-base develop feature/report)" = "$(git rev-parse develop)" ]; then
    pass "feature/report 已建立在最新的 develop 之上"
  else
    fail "基底還不是最新的 develop（rebase 尚未完成）"
  fi
  local n; n=$(git rev-list --count develop..feature/report)
  [ "$n" -eq 2 ] && pass "你的 2 個 commit 都在（沒有遺失或重複）" \
    || fail "develop..feature/report 有 $n 個 commit，預期 2 個"
  git show feature/report:d3.txt >/dev/null 2>&1 \
    && pass "已包含 develop 的最新內容" || fail "看不到 develop 的新功能"
  local parents; parents=$(git rev-list --parents -n1 HEAD | wc -w | tr -d ' ')
  [ "$parents" -eq 2 ] && pass "歷史是線性的（沒有合併節點）" \
    || info "  ${C_Y}⚠${C_RST} HEAD 是合併節點 —— 你用了 merge，題目要求的是 rebase"
  learn "${C_B}rebase 或 merge？${C_RST}
    自己的 feature 分支要同步 develop  → ${C_C}rebase${C_RST}（歷史乾淨）
    多人共用的分支要同步              → ${C_C}merge${C_RST}（不改寫別人的 SHA）
    feature 合回 develop              → ${C_C}merge --no-ff${C_RST}（保留功能邊界）
  rebase 後要推送必須用 ${C_C}--force-with-lease${C_RST}，${C_R}絕不用 --force${C_RST}。"
}
solve_10() { git rebase -q develop; }

# ══════════════════════════════════════════════════════════
# 11. reflog 救援
# ══════════════════════════════════════════════════════════
setup_11() {
  local d; d=$(dir_of 11); init_repo "$d"
  echo "base" > base.txt; qc "chore: 初始化"
  git switch -q -c develop
  echo "f1" > f1.txt; qc "feat: 重要功能一"
  echo "f2" > f2.txt; qc "feat: 重要功能二"
  echo "f3" > f3.txt; qc "feat: 重要功能三"
  git reset -q --hard HEAD~3      # 災難：三個 commit 不見了
}
task_11() {
  info "  ${C_R}災難現場${C_RST}：有人誤下了 git reset --hard HEAD~3，三個 commit 消失了。"
  info "  目前的 log："
  git log --oneline | sed 's/^/    /'
  task "請把那 3 個 commit（重要功能一、二、三）${C_B}完整救回 develop${C_RST}。"
  tip "${C_B}Git 幾乎刪不掉東西。${C_RST}
  ${C_C}git reflog${C_RST} 記錄了 HEAD 的每一次移動（預設保留 90 天，只存在本機）。
  就算 reset --hard、就算誤刪分支，都能從這裡找回來。

  這是所有 Git 指令裡${C_B}最值得先背起來的一個${C_RST}。"
}
hint_11() {
  info "  git reflog
  # 找出 reset 之前那一行，例如：
  #   8b4d9e HEAD@{1}: commit: feat: 重要功能三
  git reset --hard HEAD@{1}       # 或直接用該 SHA
  git log --oneline"
}
check_11() {
  [ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ] \
    && pass "位於 develop" || fail "應停留在 develop"
  local missing=0
  for f in f1 f2 f3; do
    git show "HEAD:$f.txt" >/dev/null 2>&1 || missing=$((missing+1))
  done
  [ "$missing" -eq 0 ] && pass "三個 commit 的內容全部救回" \
    || fail "還有 $missing 個功能沒救回來"
  local n; n=$(git rev-list --count HEAD)
  [ "$n" -ge 4 ] && pass "歷史完整（$n 個 commit）" || fail "歷史仍不完整（只有 $n 個 commit）"
  learn "reflog 只存在${C_B}你的本機${C_RST}，且只記錄${C_B}你的${C_RST} HEAD 移動。
  同事的機器上有他自己的 reflog —— 所以團隊誤刪遠端分支時，
  ${C_B}任何一個有舊版的人${C_RST}都能救回來。
  真正救不回的只有：從未 commit 過的東西。所以${C_B}常 commit${C_RST}。"
}
solve_11() {
  local sha; sha=$(git reflog --format='%H %gs' | grep 'commit: feat: 重要功能三' | head -1 | cut -d' ' -f1)
  git reset -q --hard "$sha"
}

# ══════════════════════════════════════════════════════════
# 12. 完整 GitFlow 小循環
# ══════════════════════════════════════════════════════════
setup_12() {
  local d; d=$(dir_of 12); init_repo "$d"
  echo "1.0.0" > VERSION
  echo "# Shop" > README.md
  qc "chore: 初始化專案"
  git tag -a v1.0.0 -m "Release 1.0.0"
  git switch -q -c develop
}
task_12() {
  task "把整套 GitFlow 走一遍。目前有 main(v1.0.0) 與 develop。

    ${C_B}① Feature${C_RST}
       從 develop 開 ${C_C}feature/checkout${C_RST}
       新增 checkout.js，commit 訊息 ${C_C}feat(checkout): 新增結帳流程${C_RST}
       用 ${C_B}--no-ff${C_RST} 合回 develop，然後刪除該分支

    ${C_B}② Release${C_RST}
       從 develop 開 ${C_C}release/1.1.0${C_RST}
       把 VERSION 改成 ${C_C}1.1.0${C_RST}，commit 訊息 ${C_C}chore(release): bump to 1.1.0${C_RST}

    ${C_B}③ 完成發版${C_RST}
       release ${C_B}--no-ff${C_RST} 合進 main，打 annotated tag ${C_C}v1.1.0${C_RST}（訊息 Release 1.1.0）
       release ${C_B}--no-ff${C_RST} 合回 develop
       刪除 release 分支，最後停在 develop"
  tip "最常被忘記的是${C_B}最後一步：合回 develop${C_RST}。
  漏掉它，release 上的版本號與 QA 修正就會在下一版消失（退版 bug）。
  這也是 GitFlow 新手最常踩的坑。"
}
hint_12() {
  info "  # ①
  git switch -c feature/checkout develop
  echo 'checkout' > checkout.js
  git add . && git commit -m \"feat(checkout): 新增結帳流程\"
  git switch develop
  git merge --no-ff feature/checkout -m \"Merge branch 'feature/checkout' into develop\"
  git branch -d feature/checkout
  # ②
  git switch -c release/1.1.0
  echo '1.1.0' > VERSION
  git commit -am \"chore(release): bump to 1.1.0\"
  # ③
  git switch main
  git merge --no-ff release/1.1.0 -m \"Merge branch 'release/1.1.0'\"
  git tag -a v1.1.0 -m \"Release 1.1.0\"
  git switch develop
  git merge --no-ff release/1.1.0 -m \"Merge branch 'release/1.1.0' into develop\"
  git branch -d release/1.1.0"
}
check_12() {
  git show develop:checkout.js >/dev/null 2>&1 \
    && pass "① feature 已合入 develop" || fail "① develop 上找不到 checkout.js"
  git show-ref -q --verify refs/heads/feature/checkout \
    && fail "① feature/checkout 尚未刪除" || pass "① feature 分支已清理"

  [ "$(git cat-file -t v1.1.0 2>/dev/null)" = "tag" ] \
    && pass "③ v1.1.0 是 annotated tag" || fail "③ v1.1.0 不存在或不是 annotated tag"
  [ "$(git rev-list -n1 v1.1.0 2>/dev/null)" = "$(git rev-parse main 2>/dev/null)" ] \
    && pass "③ v1.1.0 打在 main 上" || fail "③ v1.1.0 沒有指向 main 的 HEAD"

  [ "$(git show main:VERSION 2>/dev/null)" = "1.1.0" ] \
    && pass "③ main 的 VERSION 是 1.1.0" || fail "③ main 的 VERSION 不是 1.1.0"
  git show main:checkout.js >/dev/null 2>&1 \
    && pass "③ 功能已隨 release 上線" || fail "③ main 上找不到 checkout.js"

  if [ "$(git show develop:VERSION 2>/dev/null)" = "1.1.0" ]; then
    pass "③ ★ release 已合回 develop（VERSION 同步）"
  else
    fail "③ ★ release 沒有合回 develop —— 這是 GitFlow 最常見的錯誤（下一版會退版）"
  fi

  local p; p=$(git rev-list --parents -n1 main | wc -w | tr -d ' ')
  [ "$p" -ge 3 ] && pass "③ main 上是合併節點（用了 --no-ff）" \
    || fail "③ main 的合併是 fast-forward，少了 --no-ff"

  git show-ref -q --verify refs/heads/release/1.1.0 \
    && fail "③ release/1.1.0 尚未刪除" || pass "③ release 分支已清理"
  [ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ] \
    && pass "最終停留在 develop" || fail "最終應停留在 develop"

  echo
  info "  你建立的歷史："
  git log --oneline --graph --decorate --all | head -14 | sed 's/^/    /'
  learn "恭喜，你已經完整走過一次 GitFlow。
  接下來可以跑 ${C_C}./scenarios/simulate.sh all${C_RST} 看 26 種真實場景，
  特別是${C_B}情境 10（release 進行中發生 hotfix）${C_RST}——
  那是實務上最容易做錯、也最容易造成回歸 bug 的一題。"
}
solve_12() {
  git switch -q -c feature/checkout develop
  echo "checkout" > checkout.js
  git add . && git commit -q -m "feat(checkout): 新增結帳流程"
  git switch -q develop
  git merge -q --no-ff feature/checkout -m "Merge branch 'feature/checkout' into develop"
  git branch -q -d feature/checkout
  git switch -q -c release/1.1.0
  echo "1.1.0" > VERSION
  git commit -q -am "chore(release): bump to 1.1.0"
  git switch -q main
  git merge -q --no-ff release/1.1.0 -m "Merge branch 'release/1.1.0'"
  git tag -a v1.1.0 -m "Release 1.1.0"
  git switch -q develop
  git merge -q --no-ff release/1.1.0 -m "Merge branch 'release/1.1.0' into develop"
  git branch -q -d release/1.1.0
}

# ══════════════════════════════════════════════════════════
# 目錄與派工
# ══════════════════════════════════════════════════════════
TITLES=(
  "" \
  "第一個 commit：add / commit / .gitignore" \
  "三大區域：工作目錄 / 暫存區 / 版本庫" \
  "分支：branch / switch，建立 GitFlow 骨架" \
  "合併：fast-forward vs --no-ff" \
  "★ 製造並解決合併衝突" \
  "標籤：annotated vs lightweight tag" \
  "撤銷三兄弟：restore / reset / revert" \
  "stash：把做到一半的工作收起來" \
  "cherry-pick：只挑一個 commit" \
  "rebase：把分支換基底" \
  "reflog：救回 reset --hard 掉的 commit" \
  "★ 完整 GitFlow 小循環（總複習）" \
)
LEVELS=( "" "⭐" "⭐" "⭐" "⭐⭐" "⭐⭐" "⭐" "⭐⭐" "⭐⭐" "⭐⭐" "⭐⭐⭐" "⭐⭐" "⭐⭐⭐" )

usage() {
  cat <<EOF

${C_B}Git 互動演練場${C_RST}  ——  自己動手，由它驗收

  ${C_C}$0 list${C_RST}          列出 $TOTAL 個練習
  ${C_C}$0 start <n>${C_RST}     佈置練習環境並顯示任務
  ${C_C}$0 check <n>${C_RST}     驗收你的成果
  ${C_C}$0 hint  <n>${C_RST}     看提示（不含完整答案）
  ${C_C}$0 solve <n>${C_RST}     看解答並自動做完
  ${C_C}$0 reset <n>${C_RST}     重置這一題
  ${C_C}$0 clean${C_RST}         清除所有練習

  ${C_B}建議流程${C_RST}
    1. ${C_C}$0 start 1${C_RST}
    2. ${C_C}cd $ROOT/d1${C_RST}   ← 在這裡下你自己的 git 指令
    3. ${C_C}$0 check 1${C_RST}    ← 回來驗收（在哪個目錄執行都可以）
    4. 卡住就 ${C_C}hint${C_RST}，真的想不出來才 ${C_C}solve${C_RST}

  練習目錄：$ROOT

EOF
}

list_drills() {
  echo
  echo "${C_B} #    難度      練習${C_RST}"
  echo " ──────────────────────────────────────────────────────────────"
  local i
  for i in $(seq 1 $TOTAL); do
    local mark="  "
    [ -d "$(dir_of "$i")" ] && mark="${C_G}▸${C_RST} "
    printf " %s%-3s %-9s %s\n" "$mark" "$i" "${LEVELS[$i]}" "${TITLES[$i]}"
  done
  echo
  echo "${C_DIM} ${C_G}▸${C_DIM} = 已佈置的練習${C_RST}"
  echo "${C_DIM} 1-3 基礎操作 · 4-6 分支與標籤 · 7-11 救援與改寫 · 12 總複習${C_RST}"
  echo
}

valid_n() {
  case "${1:-}" in
    ''|*[!0-9]*) echo "${C_R}✘${C_RST} 請提供 1-$TOTAL 的練習編號"; return 1 ;;
  esac
  if [ "$1" -lt 1 ] || [ "$1" -gt "$TOTAL" ]; then
    echo "${C_R}✘${C_RST} 練習編號需在 1-$TOTAL 之間"; return 1
  fi
  return 0
}

need_setup() {
  local d; d=$(dir_of "$1")
  if [ ! -d "$d/.git" ]; then
    echo "${C_Y}⚠${C_RST} 練習 $1 尚未佈置，請先執行：${C_C}$0 start $1${C_RST}"
    return 1
  fi
  cd "$d" || return 1
}

cmd_start() {
  valid_n "$1" || return 1
  mkdir -p "$ROOT"
  local d; d=$(dir_of "$1")
  if [ -d "$d/.git" ]; then
    echo "${C_Y}⚠${C_RST} 練習 $1 已存在。重新佈置請用：${C_C}$0 reset $1${C_RST}"
    echo "   顯示任務："
  else
    "setup_$1"
  fi
  cd "$d" || return 1
  box "練習 $1  ${LEVELS[$1]}  ${TITLES[$1]}"
  "task_$1"
  where "$d"
}

cmd_check() {
  valid_n "$1" || return 1
  need_setup "$1" || return 1
  box "驗收：練習 $1  ${TITLES[$1]}"
  FAILED=0
  "check_$1"
  echo
  if [ "$FAILED" -eq 0 ]; then
    echo "${C_G}${C_B}🎉 全部通過！${C_RST}"
    local nx=$(( $1 + 1 ))
    [ "$nx" -le "$TOTAL" ] && echo "   下一題：${C_C}$0 start $nx${C_RST}"
  else
    echo "${C_Y}還有 $FAILED 項未達成。${C_RST}"
    echo "   看提示：${C_C}$0 hint $1${C_RST}   ｜   重來：${C_C}$0 reset $1${C_RST}"
  fi
  echo
}

cmd_hint() {
  valid_n "$1" || return 1
  need_setup "$1" || return 1
  box "提示：練習 $1"
  "hint_$1"
  echo
}

cmd_solve() {
  valid_n "$1" || return 1
  need_setup "$1" || return 1
  box "解答：練習 $1"
  "hint_$1"
  echo
  echo "${C_Y}▶ 已依上述解答自動執行完畢，可用 git log 檢視結果${C_RST}"
  "solve_$1"
  echo
  git log --oneline --graph --decorate --all 2>/dev/null | head -12 | sed 's/^/  /'
  echo
}

cmd_reset() {
  valid_n "$1" || return 1
  mkdir -p "$ROOT"
  "setup_$1"
  echo "${C_G}✔${C_RST} 練習 $1 已重置"
  cd "$(dir_of "$1")" || return 1
  box "練習 $1  ${LEVELS[$1]}  ${TITLES[$1]}"
  "task_$1"
  where "$(dir_of "$1")"
}

main() {
  command -v git >/dev/null 2>&1 || { echo "找不到 git"; exit 1; }
  [ $# -eq 0 ] && { usage; exit 0; }
  case "$1" in
    list|-l|--list) list_drills ;;
    clean)          rm -rf "$ROOT"; echo "${C_G}✔${C_RST} 已清除 $ROOT" ;;
    start)          cmd_start "${2:-}" ;;
    check)          cmd_check "${2:-}" ;;
    hint)           cmd_hint  "${2:-}" ;;
    solve)          cmd_solve "${2:-}" ;;
    reset)          cmd_reset "${2:-}" ;;
    -h|--help)      usage ;;
    *)              echo "未知指令：$1"; usage; exit 1 ;;
  esac
}

main "$@"

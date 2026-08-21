#!/usr/bin/env bash
#
# 文件與腳本一致性檢查（防漂移）
# ------------------------------------------------------------
# 手冊裡的題目/情境清單是「手寫」的，腳本才是「真相」。
# 兩邊很容易在改動後失去同步，這支腳本負責把差異抓出來。
#
#   ./scripts/verify-docs.sh
#
# 檢查項目：
#   1. 演練題數與標題（practice.sh ↔ README 第 13 章）
#   2. 情境數與編號（simulate.sh ↔ docs/scenarios.md）
#   3. Pipeline 檔案與文件引用（ci-examples/ ↔ docs/pipelines.md）
#   4. 所有 Markdown 連結（錨點與相對路徑）
#   5. 程式碼圍籬平衡
#   6. Shell 語法與 YAML 可解析性
#
# 離開碼：0 = 全部通過，1 = 有不一致
# ------------------------------------------------------------

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; D=$'\033[2m'; N=$'\033[0m'
else
  R=''; G=''; Y=''; B=''; D=''; N=''
fi

FAILED=0
sec()  { echo; echo "${B}$*${N}"; }
ok()   { echo "  ${G}✔${N} $*"; }
bad()  { echo "  ${R}✘${N} $*"; FAILED=$((FAILED + 1)); }
warn() { echo "  ${Y}⚠${N} $*"; }

command -v python3 >/dev/null 2>&1 || {
  echo "${R}需要 python3${N}"; exit 1; }

# ── 1-4：交給 python 做結構化比對 ──────────────────────
python3 - <<'PY'
import os, re, sys

fail = 0
def ok(m):   print(f"  \033[32m✔\033[0m {m}")
def bad(m):
    global fail; fail += 1
    print(f"  \033[31m✘\033[0m {m}")
def sec(m):  print(f"\n\033[1m{m}\033[0m")

def read(p):
    return open(p, encoding='utf-8').read()

def norm(s):
    """比對用正規化：去掉 markdown 強調符號與反引號、收斂空白"""
    return re.sub(r'\s+', ' ', re.sub(r'[`*]', '', s)).strip()

def bash_array(path, name):
    """讀出 shell 陣列 NAME=( "a" \ "b" ... ) 的字串元素"""
    src = read(path)
    m = re.search(rf'^{name}=\((.*?)^\)', src, re.S | re.M)
    if not m:
        return None
    return re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))

# ── 1. 演練：practice.sh ↔ README 第 13 章 ─────────────
sec("1. 互動演練場（practice.sh ↔ README 第 13 章）")
ps = read('drills/practice.sh')

setups = sorted(int(n) for n in re.findall(r'^setup_(\d+)\(\) \{', ps, re.M))
m = re.search(r'^TOTAL=(\d+)', ps, re.M)
total = int(m.group(1)) if m else -1
titles = bash_array('drills/practice.sh', 'TITLES') or []
titles = titles[1:]  # 首欄是佔位空字串

rows = re.findall(r'^\| (\d+) \| [⭐]+ \| (.+?) \|',
                  re.search(r'### 13\.2 .*?\n(.*?)\n### 13\.3', read('README.md'), re.S).group(1),
                  re.M)

if setups == list(range(1, total + 1)):
    ok(f"setup_N 函式編號連續且完整：1–{total}")
else:
    bad(f"setup_N 編號不連續或與 TOTAL({total}) 不符：{setups}")

for n in setups:
    missing = [f for f in ('task', 'check', 'hint', 'solve')
               if not re.search(rf'^{f}_{n}\(\) \{{', ps, re.M)]
    if missing:
        bad(f"第 {n} 題缺少函式：{', '.join(f'{f}_{n}()' for f in missing)}")
if not any(re.search(rf'^{f}_{n}\(\) \{{', ps, re.M) is None
           for n in setups for f in ('task', 'check', 'hint', 'solve')):
    ok("每題的 setup / task / check / hint / solve 五個函式齊備")

if len(titles) == total:
    ok(f"TITLES 陣列長度正確：{total}")
else:
    bad(f"TITLES 有 {len(titles)} 筆，TOTAL 為 {total}")

if len(rows) == total:
    ok(f"README 第 13.2 節表格有 {total} 列")
else:
    bad(f"README 表格有 {len(rows)} 列，腳本有 {total} 題")

for i, (num, title) in enumerate(rows):
    if int(num) != i + 1:
        bad(f"README 表格第 {i+1} 列編號為 {num}")
        continue
    if i < len(titles) and norm(title) != norm(titles[i]):
        bad(f"第 {num} 題標題不一致\n"
            f"      腳本：{norm(titles[i])}\n"
            f"      文件：{norm(title)}")
if rows and all(norm(t) == norm(titles[i]) for i, (_, t) in enumerate(rows) if i < len(titles)):
    ok("每一題的標題文字與腳本一致")

# ── 2. 情境：simulate.sh ↔ docs/scenarios.md ───────────
sec("2. 情境模擬器（simulate.sh ↔ docs/scenarios.md）")
sm = read('scenarios/simulate.sh')
funcs = sorted(int(n) for n in re.findall(r'^s(\d+)\(\) \{', sm, re.M))
s_titles = bash_array('scenarios/simulate.sh', 'TITLES') or []
s_titles = [t for t in s_titles[1:]]
groups = bash_array('scenarios/simulate.sh', 'GROUPS') or []
groups = [g for g in groups[1:]]

doc = read('docs/scenarios.md')
heads = sorted(int(n) for n in re.findall(r'^#### 情境 (\d+)', doc, re.M))

n_scen = len(funcs)
if funcs == list(range(1, n_scen + 1)):
    ok(f"sN 函式編號連續且完整：1–{n_scen}")
else:
    bad(f"sN 編號不連續：{funcs}")

for label, arr in (('TITLES', s_titles), ('GROUPS', groups)):
    if len(arr) == n_scen:
        ok(f"{label} 陣列長度正確：{n_scen}")
    else:
        bad(f"{label} 有 {len(arr)} 筆，情境函式有 {n_scen} 個")

if heads == list(range(1, n_scen + 1)):
    ok(f"docs/scenarios.md 有 1–{n_scen} 完整 {len(heads)} 個情境小節")
else:
    missing = sorted(set(range(1, n_scen + 1)) - set(heads))
    extra = sorted(set(heads) - set(range(1, n_scen + 1)))
    bad(f"文件情境編號與腳本不符（缺 {missing or '無'}、多 {extra or '無'}）")

m = re.search(r'^TOTAL=(\d+)', sm, re.M)
for pat, what in ((r'(\d+) 種真實場景', 'README 目錄'),
                  (r'(\d+) 個情境', 'README 目錄')):
    for src, name in (('README.md', 'README'), ('docs/scenarios.md', 'scenarios.md')):
        for hit in set(re.findall(pat, read(src))):
            if int(hit) != n_scen:
                bad(f"{name} 寫著「{hit} {what.split()[-1]}」，實際為 {n_scen}")

# ── 3. Pipeline 檔案 ↔ docs/pipelines.md ───────────────
sec("3. Pipeline 檔案（ci-examples/ ↔ docs/pipelines.md）")
wf_dir = 'ci-examples/github-actions'
wfs = sorted(f for f in os.listdir(wf_dir) if f.endswith('.yml')) if os.path.isdir(wf_dir) else []
pipe_doc = read('docs/pipelines.md') if os.path.exists('docs/pipelines.md') else ''
if wfs:
    ok(f"找到 {len(wfs)} 個 workflow 檔案")
else:
    bad(f"{wf_dir} 下找不到任何 .yml")
for f in wfs:
    if f in pipe_doc:
        ok(f"{f} 已在文件中說明")
    else:
        bad(f"{f} 未被 docs/pipelines.md 引用")
if os.path.isdir('.github/workflows'):
    bad(".github/workflows/ 存在 —— GitHub 會自動觸發 Actions（本專案刻意停用）")
else:
    ok(".github/workflows/ 不存在，Actions 維持停用")

# ── 4. Markdown 連結 ──────────────────────────────────
sec("4. Markdown 連結與圍籬")
mds = ['README.md'] + [os.path.join('docs', f) for f in sorted(os.listdir('docs'))
                       if f.endswith('.md')] if os.path.isdir('docs') else ['README.md']

def slug(t):
    t = re.sub(r'`', '', t.strip())
    t = re.sub(r'[^\w一-鿿\- ]', '', t.lower())
    return t.strip().replace(' ', '-')

anchors = {}
for md in mds:
    txt = read(md)
    infence = False
    s = set()
    for ln in txt.split('\n'):
        if ln.startswith('```'):
            infence = not infence
            continue
        if infence:
            continue
        m2 = re.match(r'^#{1,6}\s+(.*)$', ln)
        if m2:
            s.add(slug(m2.group(1)))
    anchors[md] = s

broken = 0
for md in mds:
    txt = read(md)
    base = os.path.dirname(md)
    for link in re.findall(r'\]\(([^)\s]+)\)', txt):
        if link.startswith(('http://', 'https://', 'mailto:')):
            continue
        path, _, frag = link.partition('#')
        if path == '':
            target = md
        else:
            target = os.path.normpath(os.path.join(base, path))
            if not os.path.exists(target):
                bad(f"{md}: 連結指向不存在的路徑 → {link}")
                broken += 1
                continue
        if frag:
            if target not in anchors:
                if target.endswith('.md'):
                    bad(f"{md}: 無法檢查錨點（未納入掃描）→ {link}")
                    broken += 1
                continue
            if frag not in anchors[target]:
                bad(f"{md}: 錨點不存在 → {link}")
                broken += 1
if broken == 0:
    ok(f"{len(mds)} 個 Markdown 檔的所有連結與錨點皆有效")

for md in mds:
    cnt = read(md).count('\n```')
    if cnt % 2 == 0:
        ok(f"{md} 程式碼圍籬平衡（{cnt // 2} 個區塊）")
    else:
        bad(f"{md} 程式碼圍籬不平衡（{cnt} 個 ``` 標記）")

sys.exit(1 if fail else 0)
PY
[ $? -ne 0 ] && FAILED=$((FAILED + 1))

# ── 5. Shell 語法 ─────────────────────────────────────
sec "5. Shell 腳本語法"
for f in drills/practice.sh scenarios/simulate.sh scripts/deploy.sh scripts/verify-docs.sh; do
  if bash -n "$f" 2>/dev/null; then ok "$f"; else bad "$f 語法錯誤"; fi
done

# ── 6. YAML ───────────────────────────────────────────
sec "6. YAML 可解析性"
if command -v yq >/dev/null 2>&1; then
  for f in ci-examples/github-actions/*.yml k8s/base/*.yaml kind-cluster.yaml; do
    [ -e "$f" ] || continue
    if yq e 'true' "$f" >/dev/null 2>&1; then ok "$f"; else bad "$f 無法解析"; fi
  done
else
  warn "找不到 yq，略過 YAML 檢查（brew install yq）"
fi

# ── 總結 ──────────────────────────────────────────────
echo
if [ "$FAILED" -eq 0 ]; then
  echo "${G}${B}✅ 全部通過 —— 文件與腳本一致${N}"
  exit 0
else
  echo "${R}${B}❌ 有 $FAILED 個項目不一致，請修正後再提交${N}"
  exit 1
fi

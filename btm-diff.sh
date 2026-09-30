#!/bin/zsh
# btm-diff.sh —— 比较两个快照，输出改动清单
#
# 用法：
#   ./btm-diff.sh snapshots/before-20260929T100000  snapshots/after-20260929T180000
#   ./btm-diff.sh snapshots/latest  snapshots/after-*  --out /tmp/报告
#
# 两个目录都要是 btm.sh 产出的快照目录（里面应有 btm_items.tsv）。
# 默认把 changes.md / changes.csv 写进「对比快照」目录。

emulate -L zsh
setopt no_nomatch

SCRIPT_DIR=${0:A:h}
AWK=/usr/bin/awk

if [[ $# -lt 2 ]]; then
  print -ru2 -- "用法: btm-diff.sh <基线快照目录> <对比快照目录> [--out <输出目录>]"
  exit 2
fi

BASE=${1:A}
NEW=${2:A}
shift 2
OUT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --out) OUT=${2:A}; shift 2 ;;
    -h|--help) print -r -- "用法: btm-diff.sh <基线> <对比> [--out <目录>]"; exit 0 ;;
    *) print -ru2 -- "未知参数：$1"; exit 2 ;;
  esac
done

# 允许直接给软链目录（snapshots/latest）
BT="$BASE/btm_items.tsv"
NT="$NEW/btm_items.tsv"

if [[ ! -f $BT ]]; then
  print -ru2 -- "基线目录里没有 btm_items.tsv：$BASE"
  print -ru2 -- "（请用 btm.sh 产出的快照目录；若你只有旧版目录，先跑一次：./btm.sh -f <旧目录>/dumpbtm.txt -o <旧目录的父目录>）"
  exit 1
fi
if [[ ! -f $NT ]]; then
  print -ru2 -- "对比目录里没有 btm_items.tsv：$NEW"
  exit 1
fi

[[ -n $OUT ]] || OUT="$NEW"
/bin/mkdir -p "$OUT"

MDFILE="$OUT/changes.md"
CSVFILE="$OUT/changes.csv"

TMP=$(/usr/bin/mktemp -d -t btmdiff)
trap 'rm -rf "$TMP"' EXIT INT TERM

# 复用 btm-emit.awk 的字段中文名映射，避免两处维护
"$AWK" -v MODE=colmap -f "$SCRIPT_DIR/btm-emit.awk" "$BT" > "$TMP/colmap.tsv"

BASEAT=""
NEWAT=""
[[ -f "$BASE/capture.txt" ]] && BASEAT=$(/usr/bin/awk -F': ' '/^captured_at:/{print $2}' "$BASE/capture.txt")
[[ -f "$NEW/capture.txt"  ]] && NEWAT=$(/usr/bin/awk -F': ' '/^captured_at:/{print $2}' "$NEW/capture.txt")

LC_ALL=C "$AWK" \
  -v MAP="$TMP/colmap.tsv" \
  -v MDFILE="$MDFILE" -v CSVFILE="$CSVFILE" \
  -v BASEDIR="$BASE" -v NEWDIR="$NEW" \
  -v BASEAT="$BASEAT" -v NEWAT="$NEWAT" \
  -f "$SCRIPT_DIR/btm-diff.awk" "$BT" "$NT"

print -r -- ""
print -r -- "报告："
print -r -- "  $MDFILE"
print -r -- "  $CSVFILE"

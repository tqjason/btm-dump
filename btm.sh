#!/bin/zsh
# btm.sh —— macOS 后台项（sfltool dumpbtm）结构化采集 / 解析 / 导出
#
# 一次运行同时产出四种格式：
#   btm_items.tsv    无损中间格式（制表符分隔，前后比对直接用这份）
#   btm_items.csv    全字段表格（UTF-8 BOM，Excel / Numbers / 腾讯文档直接打开不乱码）
#   btm_items.json   结构化数据（列表字段保留为数组，含列的中文名与分组）
#   btm_items.html   单文件浏览版：表格视图（列选择 / 筛选 / 排序 / 导出）+ 8 种关系树 + 字段说明
#
# 纯 zsh + 系统自带 awk，不需要 Python、不需要装任何东西。
#
# 用法：
#   ./btm.sh                          # 就地采集当前机器并导出（会调 sudo）
#   ./btm.sh -l before                # 打标签，便于前后比对
#   ./btm.sh -f dumpbtm.txt -l before # 用已有的 dump 文本，不联网、不调 sudo
#   ./btm.sh -s vendor -n             # 指定排序口径 + 清空 (null)
#
# 排序口径：scope(默认) / type / vendor / identifier / name / status / file

emulate -L zsh
setopt no_nomatch

SCRIPT_DIR=${0:A:h}
AWK=/usr/bin/awk
SORT=/usr/bin/sort
CUT=/usr/bin/cut

LABEL="snapshot"
OUTDIR="$SCRIPT_DIR/snapshots"
RAWFILE=""
SORTP="scope"
NULLMODE=0
QUIET=0
RERENDER=""

usage() {
  print -r -- "用法: btm.sh [-f <dumpbtm.txt>] [-l <标签>] [-o <输出目录>] [-s <排序口径>] [-n] [-q]"
  print -r -- "      btm.sh -r <快照目录>      重新渲染该快照的 HTML（模板更新后用，不动数据）"
  print -r -- ""
  print -r -- "  -f <文件>   读取已有的 dumpbtm 文本（不给则实时执行 sudo sfltool dumpbtm）"
  print -r -- "  -l <标签>   快照标签，默认 snapshot"
  print -r -- "  -o <目录>   输出根目录，默认 <脚本目录>/snapshots"
  print -r -- "  -s <口径>   scope|type|vendor|identifier|name|status|file，默认 scope"
  print -r -- "  -n          把原值 \"(null)\" 清空，表格更干净（默认原样保留）"
  print -r -- "  -q          安静模式，不打印摘要"
  print -r -- "  -r <目录>   只重新渲染 HTML：读该目录已有的 btm_items.json 重新套当前模板"
  print -r -- "  -h          显示本帮助"
}

while getopts ":f:l:o:s:r:nqh" opt; do
  case $opt in
    f) RAWFILE=$OPTARG ;;
    l) LABEL=$OPTARG ;;
    o) OUTDIR=$OPTARG ;;
    s) SORTP=$OPTARG ;;
    r) RERENDER=$OPTARG ;;
    n) NULLMODE=1 ;;
    q) QUIET=1 ;;
    h) usage; exit 0 ;;
    \?) print -ru2 -- "未知选项: -$OPTARG"; usage; exit 2 ;;
    :)  print -ru2 -- "选项 -$OPTARG 需要一个参数"; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- 重新渲染模式
# 只换 HTML，不重新解析：数据文件（tsv/csv/json）与采集信息原样不动。
if [[ -n $RERENDER ]]; then
  [[ -d $RERENDER ]] || { print -ru2 -- "找不到快照目录：$RERENDER"; exit 1 }
  RDIR=${RERENDER:A}
  [[ -f $RDIR/btm_items.json ]] || { print -ru2 -- "该目录没有 btm_items.json：$RDIR"; exit 1 }
  [[ -f $SCRIPT_DIR/btm-view.tpl.html ]] || { print -ru2 -- "缺少模板：$SCRIPT_DIR/btm-view.tpl.html"; exit 1 }
  "$AWK" -v DATA="$RDIR/btm_items.json" '
    $0 == "<!--BTM_DATA-->" { while ((getline line < DATA) > 0) print line; close(DATA); next }
    { print }
  ' "$SCRIPT_DIR/btm-view.tpl.html" > "$RDIR/btm_items.html"
  print -r -- "已用当前模板重新渲染：$RDIR/btm_items.html"
  print -r -- "（tsv / csv / json / capture.txt / meta.json 未改动）"
  exit 0
fi

case $SORTP in
  scope|type|vendor|identifier|name|status|file) ;;
  *) print -ru2 -- "排序口径必须是 scope|type|vendor|identifier|name|status|file"; exit 2 ;;
esac

for f in "$SCRIPT_DIR/btm-extract.awk" "$SCRIPT_DIR/btm-emit.awk" "$SCRIPT_DIR/btm-view.tpl.html"; do
  [[ -f $f ]] || { print -ru2 -- "缺少必需文件：$f"; exit 1 }
done

STAMP=$(/bin/date +%Y%m%dT%H%M%S)
CAPTURED_AT=$(/bin/date +%Y-%m-%dT%H:%M:%S%z)
SNAP_DIR="$OUTDIR/$LABEL-$STAMP"
TMP_DIR=$(/usr/bin/mktemp -d -t btm)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

/bin/mkdir -p "$SNAP_DIR"
TSV="$SNAP_DIR/btm_items.tsv"
CSV="$SNAP_DIR/btm_items.csv"
JSON="$SNAP_DIR/btm_items.json"
HTML="$SNAP_DIR/btm_items.html"
META="$SNAP_DIR/meta.json"
CAPTURE="$SNAP_DIR/capture.txt"

# ------------------------------------------------------------------ 1. 取原始文本
if [[ -n $RAWFILE ]]; then
  [[ -f $RAWFILE ]] || { print -ru2 -- "找不到文件：$RAWFILE"; exit 1 }
  /bin/cp "$RAWFILE" "$SNAP_DIR/dumpbtm.txt"
  SRC_ABS=${RAWFILE:A}
  MODE="file"
else
  print -r -- "正在执行：sudo sfltool dumpbtm > $SNAP_DIR/dumpbtm.txt"
  # 沿用原脚本的写法：存在 SUDO_ASKPASS 时自动加 -A，避免卡在交互式密码输入
  if ! sudo ${SUDO_ASKPASS:+-A} sfltool dumpbtm > "$SNAP_DIR/dumpbtm.txt"; then
    print -ru2 -- "采集失败（可能是取消了授权，或未以可提权用户运行）。"
    rmdir "$SNAP_DIR" 2>/dev/null
    exit 1
  fi
  SRC_ABS="$SNAP_DIR/dumpbtm.txt"
  MODE="live"
fi

RAW="$SNAP_DIR/dumpbtm.txt"
[[ -s $RAW ]] || { print -ru2 -- "原始 dump 为空：$RAW"; exit 1 }

# ------------------------------------------------------------------ 2. 解析 -> 无损 TSV
"$AWK" -v SORT="$SORTP" -v HDRFILE="$TMP_DIR/hdr" -v SECFILE="$TMP_DIR/sec.tsv" \
       -v NULLMODE="$NULLMODE" -f "$SCRIPT_DIR/btm-extract.awk" "$RAW" \
  | LC_ALL=C "$SORT" -t $'\t' -k1,1 | "$CUT" -f2- > "$TMP_DIR/body.tsv"

cat "$TMP_DIR/hdr" "$TMP_DIR/body.tsv" > "$TSV"

NCOL=$(tr '\t' '\n' < "$TMP_DIR/hdr" | /usr/bin/wc -l | tr -d ' ')
NITEM=$(/usr/bin/wc -l < "$TMP_DIR/body.tsv" | tr -d ' ')
NSEC=$(( $(/usr/bin/wc -l < "$TMP_DIR/sec.tsv" | tr -d ' ') - 1 ))

[[ $NITEM -gt 0 ]] || { print -ru2 -- "解析出 0 条记录，原始文件格式可能不对：$RAW"; exit 1 }

# ------------------------------------------------------------------ 3. CSV
/usr/bin/printf '\xef\xbb\xbf' > "$CSV"
"$AWK" -v MODE=csv -v NULLMODE="$NULLMODE" -f "$SCRIPT_DIR/btm-emit.awk" "$TSV" >> "$CSV"

# ------------------------------------------------------------------ 4. JSON
HOSTNAME_S=$(/bin/hostname -s 2>/dev/null || /bin/hostname)
OSV="macOS $(/usr/bin/sw_vers -productVersion 2>/dev/null) ($(/usr/bin/sw_vers -buildVersion 2>/dev/null))"
ARCH=$(/usr/bin/uname -m)

"$AWK" -v MODE=json \
       -v SECFILE="$TMP_DIR/sec.tsv" \
       -v GENAT="$CAPTURED_AT" -v CAPAT="$CAPTURED_AT" \
       -v HOST="$HOSTNAME_S" -v OSV="$OSV" -v ARCH="$ARCH" \
       -v SRC="$SRC_ABS" -v SORTP="$SORTP" -v NULLMODE="$NULLMODE" \
       -f "$SCRIPT_DIR/btm-emit.awk" "$TSV" > "$JSON"

# ------------------------------------------------------------------ 5. HTML
"$AWK" -v DATA="$JSON" '
  $0 == "<!--BTM_DATA-->" { while ((getline line < DATA) > 0) print line; close(DATA); next }
  { print }
' "$SCRIPT_DIR/btm-view.tpl.html" > "$HTML"

# ------------------------------------------------------------------ 6. 采集信息
{
  print -r -- "captured_at: $CAPTURED_AT"
  print -r -- "host: $HOSTNAME_S"
  print -r -- "os_version: $OSV"
  print -r -- "arch: $ARCH"
  print -r -- "mode: $MODE"
  print -r -- "source: $SRC_ABS"
  print -r -- "sort_preset: $SORTP"
  print -r -- "null_as_empty: $NULLMODE"
  print -r -- "item_count: $NITEM"
  print -r -- "section_count: $NSEC"
  print -r -- "column_count: $NCOL"
  print -r -- "snapshot_dir: $SNAP_DIR"
} > "$CAPTURE"

# ------------------------------------------------------------------ 7. meta.json
jes() { local s=${1-}; s=${s//\\/\\\\}; s=${s//\"/\\\"}; print -rn -- "$s"; }

{
  print -r -- "{"
  print -r -- "  \"schema\": \"btm-meta/1\","
  print -r -- "  \"captured_at\": \"$(jes "$CAPTURED_AT")\","
  print -r -- "  \"host\": \"$(jes "$HOSTNAME_S")\","
  print -r -- "  \"os_version\": \"$(jes "$OSV")\","
  print -r -- "  \"arch\": \"$(jes "$ARCH")\","
  print -r -- "  \"mode\": \"$MODE\","
  print -r -- "  \"source\": \"$(jes "$SRC_ABS")\","
  print -r -- "  \"sort_preset\": \"$SORTP\","
  print -r -- "  \"null_as_empty\": $NULLMODE,"
  print -r -- "  \"item_count\": $NITEM,"
  print -r -- "  \"section_count\": $NSEC,"
  print -r -- "  \"column_count\": $NCOL,"
  print -r -- "  \"outputs\": [\"btm_items.tsv\", \"btm_items.csv\", \"btm_items.json\", \"btm_items.html\", \"capture.txt\", \"meta.json\"],"
  print -r -- "  \"snapshot_dir\": \"$(jes "$SNAP_DIR")\""
  print -r -- "}"
} > "$META"

# ------------------------------------------------------------------ 8. latest 软链
/bin/ln -sfn "${SNAP_DIR:t}" "$OUTDIR/latest"

# ------------------------------------------------------------------ 9. 摘要
if [[ $QUIET -eq 0 ]]; then
  print -r -- ""
  print -r -- "解析完成：$NITEM 条记录　·　$NSEC 个记录组　·　$NCOL 个字段"
  "$AWK" -F'\t' 'NR>1 { printf "  UID %-5s %s　%d 条\n", $1, $2, $5 }' "$TMP_DIR/sec.tsv"
  DUPCOL=$(/usr/bin/awk -F'\t' '{ for (i = 1; i <= NF; i++) if ($i == "dup_group") { print i; exit } }' "$TMP_DIR/hdr")
  if [[ -n $DUPCOL ]]; then
    DUPLIST=$(/usr/bin/awk -F'\t' -v c="$DUPCOL" 'NR > 1 && $c != "" { print $c }' "$TSV" \
              | LC_ALL=C "$SORT" -u | tr '\n' ' ')
    [[ -n ${DUPLIST// /} ]] && print -r -- "重复注册组：$DUPLIST（未删除任何记录，仅标记在 dup_group 列）"
  fi
  print -r -- ""
  print -r -- "输出目录：$SNAP_DIR"
  print -r -- "  btm_items.tsv    无损中间格式（前后比对用这份）"
  print -r -- "  btm_items.csv    全字段表格（UTF-8 BOM）"
  print -r -- "  btm_items.json   结构化数据"
  print -r -- "  btm_items.html   浏览版：表格 + 列选择 + 8 种关系树"
  print -r -- "  capture.txt      采集环境与计数"
  print -r -- "  meta.json        机器可读的元信息"
  print -r -- ""
  print -r -- "next: ./btm-diff.sh $OUTDIR/latest <下一个快照目录>"
fi

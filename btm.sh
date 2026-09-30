#!/bin/zsh
# btm.sh —— macOS 后台项（sfltool dumpbtm）结构化采集 / 解析 / 导出
#
# 一次运行同时产出四种格式：
#   btm_items.tsv    无损中间格式（制表符分隔，前后比对直接用这份）
#   btm_items.csv    全字段表格（UTF-8 BOM，Excel / Numbers / 腾讯文档直接打开不乱码）
#   btm_items.json   结构化数据（列表字段保留为数组，含列的中文名与分组）
#   btm_items.html   单文件浏览版：表格视图（列选择 / 筛选 / 排序 / 导出）+ 8 种关系树 + 字段说明
#
# 浏览页有两种语言形态，由 -L 决定（默认按本机系统语言自动选择）：
#   zh    中英对照（表格里「中文列名 + 原始列名」双行）
#   en    纯英文
#   both  两种各出一份（btm_items.html 中文对照 + btm_items.en.html 纯英文）
#   auto  读 macOS 首选语言：中文环境出 zh，其余出 en
# 语言只影响 HTML 的界面文案；tsv / csv / json 里的数据与列名永远是原样，前后比对不受影响。
#
# 纯 zsh + 系统自带 awk，不需要 Python、不需要装任何东西。
#
# 用法：
#   ./btm.sh                          # 就地采集当前机器并导出（会调 sudo）
#   ./btm.sh -l before                # 打标签，便于前后比对
#   ./btm.sh -f dumpbtm.txt -l before # 用已有的 dump 文本，不联网、不调 sudo
#   ./btm.sh -s vendor -n             # 指定排序口径 + 清空 (null)
#   ./btm.sh -L en                    # 浏览页出纯英文版
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
UILANG="auto"
NULLMODE=0
QUIET=0
RERENDER=""

usage() {
  print -r -- "用法: btm.sh [-f <dumpbtm.txt>] [-l <标签>] [-o <输出目录>] [-s <排序口径>] [-L <语言>] [-n] [-q]"
  print -r -- "      btm.sh -r <快照目录> [-L <语言>]   重新渲染该快照的 HTML（模板更新后用，不动数据）"
  print -r -- ""
  print -r -- "  -f <文件>   读取已有的 dumpbtm 文本（不给则实时执行 sudo sfltool dumpbtm）"
  print -r -- "  -l <标签>   快照标签，默认 snapshot"
  print -r -- "  -o <目录>   输出根目录，默认 <脚本目录>/snapshots"
  print -r -- "  -s <口径>   scope|type|vendor|identifier|name|status|file，默认 scope"
  print -r -- "  -L <语言>   浏览页语言：auto(默认)|zh|en|both"
  print -r -- "              auto —— 按本机系统语言：中文环境出 zh（中英对照），其余出 en（纯英文）"
  print -r -- "              both —— btm_items.html 出中文对照，另出一份 btm_items.en.html"
  print -r -- "  -n          把原值 \"(null)\" 清空，表格更干净（默认原样保留）"
  print -r -- "  -q          安静模式，不打印摘要"
  print -r -- "  -r <目录>   只重新渲染 HTML：读该目录已有的 btm_items.json 重新套当前模板"
  print -r -- "  -h          显示本帮助"
}

while getopts ":f:l:o:s:L:r:nqh" opt; do
  case $opt in
    f) RAWFILE=$OPTARG ;;
    l) LABEL=$OPTARG ;;
    o) OUTDIR=$OPTARG ;;
    s) SORTP=$OPTARG ;;
    L) UILANG=$OPTARG ;;
    r) RERENDER=$OPTARG ;;
    n) NULLMODE=1 ;;
    q) QUIET=1 ;;
    h) usage; exit 0 ;;
    \?) print -ru2 -- "未知选项: -$OPTARG"; usage; exit 2 ;;
    :)  print -ru2 -- "选项 -$OPTARG 需要一个参数"; exit 2 ;;
  esac
done

# ---------------------------------------------------------------- 界面语言
# auto 的判定顺序：AppleLanguages 首选语言 → AppleLocale → $LANG → en。
# 只要首选语言以 zh 开头（zh-Hans-CN / zh-Hant-TW / zh_CN …）就出中英对照版，否则出纯英文版。
detect_ui_lang() {
  local l
  l=$(/usr/bin/defaults read -g AppleLanguages 2>/dev/null \
      | "$AWK" 'match($0, /"[^"]+"/) { print substr($0, RSTART + 1, RLENGTH - 2); exit }')
  [[ -n $l ]] || l=$(/usr/bin/defaults read -g AppleLocale 2>/dev/null)
  [[ -n $l ]] || l=${LANG:-}
  case ${l:l} in
    zh*) print -rn -- zh ;;
    *)   print -rn -- en ;;
  esac
}

case $UILANG in
  auto) UILANG=$(detect_ui_lang) ;;
  zh|en|both) ;;
  *) print -ru2 -- "-L 只能是 auto|zh|en|both（收到：$UILANG）"; exit 2 ;;
esac

TPL="$SCRIPT_DIR/btm-view.tpl.html"

# ---------------------------------------------------------------- HTML 渲染
# 一次 awk 干两件事：
#   ① 把 <!--BTM_DATA--> 换成内嵌 JSON（数据永远原样，不做任何翻译）
#   ② 只保留 /* ---BTM_I18N:<语言>--- */ 那一块界面文案，另一块整段剥掉
# 顺带替换 <html lang> 与 <title> 两个占位符。
# 之所以在模板里放两套、渲染时裁掉一套，而不是做两份模板文件：逻辑只有一份，不会漂移；
# 而裁掉之后产出的 HTML 是真正单语的，文件里不夹带另一种语言。
render_html() {   # $1 = 语言(zh|en)  $2 = 目标文件
  local ui=$1 tgt=$2 hl ttl
  if [[ $ui == en ]]; then
    hl='en'
    ttl='macOS Background Items (BTM) — full fields · relationship trees'
  else
    hl='zh-CN'
    ttl='macOS 后台项清单 (BTM) — 全字段 · 关系树'
  fi
  "$AWK" -v DATA="$JSON_SRC" -v UILANG="$ui" -v HL="$hl" -v TITLE="$ttl" '
    $0 == "<!--BTM_DATA-->" { while ((getline l < DATA) > 0) print l; close(DATA); next }
    $0 == "/* ===BTM_I18N_BEGIN=== */" { ini = 1; next }
    $0 == "/* ===BTM_I18N_END=== */"   { ini = 0; next }
    ini {
      if (index($0, "/* ---BTM_I18N:") == 1) {
        s = $0
        sub(/.*---BTM_I18N:/, "", s)
        sub(/-+ \*\/[ \t]*$/, "", s)
        pick = (s == UILANG)
        next
      }
      if (pick) print
      next
    }
    { gsub(/<!--BTM_HTMLLANG-->/, HL); gsub(/<!--BTM_TITLE-->/, TITLE); print }
  ' "$TPL" > "$tgt"

  # 渲染自检：裁剪没生效就会在页面上表现为脚本报错，宁可让脚本失败也不产出坏页面。
  if "$AWK" -v UILANG="$ui" '
        index($0, "/* ---BTM_I18N:") == 1 { bad = 1 }
        /^var BTM_LANG = / { total++; if (index($0, UILANG) > 0) hit++ }
        END { exit (bad || total != 1 || hit != 1) }
      ' "$tgt"; then
    return 0
  fi
  print -ru2 -- "HTML 语言块渲染自检失败（模板标记可能被改坏）：$tgt"
  return 1
}

# ---------------------------------------------------------------- 重新渲染模式
# 只换 HTML，不重新解析：数据文件（tsv/csv/json）与采集信息原样不动。
if [[ -n $RERENDER ]]; then
  [[ -d $RERENDER ]] || { print -ru2 -- "找不到快照目录：$RERENDER"; exit 1 }
  RDIR=${RERENDER:A}
  [[ -f $RDIR/btm_items.json ]] || { print -ru2 -- "该目录没有 btm_items.json：$RDIR"; exit 1 }
  [[ -f $TPL ]] || { print -ru2 -- "缺少模板：$TPL"; exit 1 }
  JSON_SRC="$RDIR/btm_items.json"
  if [[ $UILANG == both ]]; then
    render_html zh "$RDIR/btm_items.html" || exit 1
    render_html en "$RDIR/btm_items.en.html" || exit 1
  else
    render_html "$UILANG" "$RDIR/btm_items.html" || exit 1
  fi
  print -r -- "已用当前模板重新渲染：$RDIR/btm_items.html（语言 $UILANG）"
  [[ $UILANG == both ]] && print -r -- "                         $RDIR/btm_items.en.html"
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
HTML_EN="$SNAP_DIR/btm_items.en.html"
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
JSON_SRC="$JSON"
if [[ $UILANG == both ]]; then
  render_html zh "$HTML" || exit 1
  render_html en "$HTML_EN" || exit 1
else
  render_html "$UILANG" "$HTML" || exit 1
fi

# ------------------------------------------------------------------ 6. 采集信息
{
  print -r -- "captured_at: $CAPTURED_AT"
  print -r -- "host: $HOSTNAME_S"
  print -r -- "os_version: $OSV"
  print -r -- "arch: $ARCH"
  print -r -- "mode: $MODE"
  print -r -- "source: $SRC_ABS"
  print -r -- "sort_preset: $SORTP"
  print -r -- "ui_lang: $UILANG"
  print -r -- "null_as_empty: $NULLMODE"
  print -r -- "item_count: $NITEM"
  print -r -- "section_count: $NSEC"
  print -r -- "column_count: $NCOL"
  print -r -- "snapshot_dir: $SNAP_DIR"
} > "$CAPTURE"

# ------------------------------------------------------------------ 7. meta.json
jes() { local s=${1-}; s=${s//\\/\\\\}; s=${s//\"/\\\"}; print -rn -- "$s"; }

OUTS='"btm_items.tsv", "btm_items.csv", "btm_items.json", "btm_items.html"'
[[ $UILANG == both ]] && OUTS+=', "btm_items.en.html"'
OUTS+=', "capture.txt", "meta.json"'

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
  print -r -- "  \"ui_lang\": \"$UILANG\","
  print -r -- "  \"null_as_empty\": $NULLMODE,"
  print -r -- "  \"item_count\": $NITEM,"
  print -r -- "  \"section_count\": $NSEC,"
  print -r -- "  \"column_count\": $NCOL,"
  print -r -- "  \"outputs\": [$OUTS],"
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
  print -r -- "  btm_items.html   浏览版：表格 + 列选择 + 8 种关系树（界面语言 $UILANG）"
  [[ $UILANG == both ]] && print -r -- "  btm_items.en.html  同上，纯英文版"
  print -r -- "  capture.txt      采集环境与计数"
  print -r -- "  meta.json        机器可读的元信息"
  print -r -- ""
  print -r -- "next: ./btm-diff.sh $OUTDIR/latest <下一个快照目录>"
fi

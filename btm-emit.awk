# btm-emit.awk —— 把「无损 TSV」导出为 CSV 或 JSON
#
# 用法：
#   awk -v MODE=csv  -f btm-emit.awk items.tsv
#   awk -v MODE=json -v SECFILE=sec.tsv -v SRC=... -f btm-emit.awk items.tsv
#
# 输入第一行为表头。可用 -f btm-emit.awk 直接改列名映射，其它无需改动。

BEGIN {
    FS = "\t"
    OFS = "\t"
    MODE = (MODE == "" ? "csv" : MODE)

    # ---- 列表型字段（JSON 里输出为数组）----
    LISTCOLS["type_modifiers"] = 1
    LISTCOLS["flags_list"] = 1
    LISTCOLS["assoc_bundle_ids"] = 1
    LISTCOLS["embedded_item_identifiers"] = 1

    # ---- 布尔型字段（JSON 里输出 true/false）----
    BOOLCOLS["enabled"] = 1
    BOOLCOLS["allowed"] = 1
    BOOLCOLS["visible"] = 1
    BOOLCOLS["notified"] = 1
    BOOLCOLS["hidden"] = 1

    # ---- 列的中文名与分组 ----
    m("uid",                        "记录组 UID",              "记录组")
    m("uid_domain",                 "作用域",                  "记录组")
    m("group_uuid",                 "记录组 UUID",             "记录组")
    m("sm_migrated",                "已迁移 ServiceManagement", "记录组")
    m("ls_registered",              "已注册 LaunchServices",    "记录组")

    m("seq",                        "组内序号",                "身份")
    m("uuid",                       "条目 UUID",               "身份")
    m("name",                       "名称",                    "身份")
    m("developer_name",             "开发者名称",              "身份")
    m("team_identifier",            "签名 Team ID",            "身份")

    m("type_raw",                   "类型（原文）",            "类型")
    m("type_mechanism",             "持久化机制",              "类型")
    m("type_modifiers",             "类型修饰词",              "类型")
    m("type_hex",                   "类型码",                  "类型")

    m("flags_raw",                  "标志（原文）",            "状态")
    m("flags_list",                 "标志列表",                "状态")
    m("flags_hex",                  "标志码",                  "状态")
    m("disposition_raw",            "处置状态（原文）",        "状态")
    m("disposition_hex",            "处置码",                  "状态")
    m("enabled",                    "已启用",                  "状态")
    m("allowed",                    "已允许",                  "状态")
    m("visible",                    "可见",                    "状态")
    m("notified",                   "已通知",                  "状态")
    m("hidden",                     "隐藏",                    "状态")

    m("identifier",                 "标识符",                  "标识")
    m("identifier_scope",           "作用域码",                "标识")
    m("identifier_scope_zh",        "作用域说明",              "标识")
    m("identifier_base",            "标识符基名",              "标识")

    m("url",                        "注册落点 URL",            "配置与落点")
    m("url_path",                   "配置路径（URL 指向）",    "配置与落点")
    m("config_kind",                "配置注册位置类别",        "配置与落点")
    m("config_dir",                 "配置所属目录",            "配置与落点")
    m("executable_path",            "可执行文件路径",          "配置与落点")
    m("exec_scope",                 "可执行落点类别",          "配置与落点")
    m("exec_dir",                   "可执行文件所属目录",      "配置与落点")

    m("bundle_identifier",          "Bundle ID",               "关系")
    m("bundle_key",                 "Bundle 归组键",           "关系")
    m("parent_identifier",          "父标识符",                "关系")
    m("parent_kind",                "父类型",                  "关系")
    m("assoc_bundle_ids",           "关联 Bundle IDs",         "关系")
    m("assoc_count",                "关联数量",                "关系")
    m("embedded_item_identifiers",  "嵌入项标识符",            "关系")
    m("embedded_count",             "嵌入数量",                "关系")

    m("generation",                 "代数（Generation）",      "变更")
    m("dup_group",                  "重复注册组",              "变更")
    m("match_key",                  "比对主键",                "变更")
    m("source_line",                "源文件行号",              "变更")

    m("child_count",                "子项数",                  "结构")
    m("depth",                      "归属层级",                "结构")
    m("node_path",                  "归属链",                  "结构")
    m("persistence_zh",             "机制说明",                "结构")

    if (NULLMODE == "") NULLMODE = 0
}

function m(col, zh, grp) {
    ZH[col] = zh
    GRP[col] = grp
    if (!(grp in GRPSEEN)) { GRPSEEN[grp] = 1; GRPN++; GRPORDER[GRPN] = grp }
}

# JSON 字符串转义（按字节处理，UTF-8 多字节原样通过）
function jesc(s,   o, i, c) {
    o = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\") o = o "\\\\"
        else if (c == "\"") o = o "\\\""
        else if (c == "/") o = o "\\/"            # 防止把 </script> 带进 HTML
        else if (c == "\n") o = o "\\n"
        else if (c == "\r") o = o "\\r"
        else if (c == "\t") o = o "\\t"
        else if (c in CT) o = o CT[c]
        else o = o c
    }
    return o
}

function out(s) { ON++; OUT[ON] = s }

# ---------------------------------------------------------------- 主流程
NR == 1 {
    NC = NF
    for (j = 1; j <= NC; j++) COL[j] = $j

    if (MODE == "colmap") {                 # 只输出「列名 -> 中文名」，供 diff 复用
        for (j = 1; j <= NC; j++) {
            c = COL[j]
            zh = ZH[c]; if (zh == "") zh = (substr(c, 1, 4) == "raw_" ? substr(c, 5) : c)
            print c "\t" zh
        }
        exit
    }
    if (MODE == "csv") {
        line = ""
        for (j = 1; j <= NC; j++) line = line (j == 1 ? "" : ",") "\"" COL[j] "\""
        print line
    }
    next
}

{
    if (MODE == "csv") {
        line = ""
        for (j = 1; j <= NC; j++) {
            v = $j
            if (NULLMODE == 1 && v == "(null)") v = ""
            gsub(/"/, "\"\"", v)
            line = line (j == 1 ? "" : ",") "\"" v "\""
        }
        print line
        next
    }
    ri++
    for (j = 1; j <= NC; j++) V[ri, j] = $j
}

END {
    if (MODE != "json") exit

    for (c = 0; c < 32; c++) CT[sprintf("%c", c)] = sprintf("\\u%04x", c)

    # ---- 头部 ----
    out("{")
    out("  \"schema\": \"btm-snapshot/2\",")
    out("  \"generated_at\": \"" jesc(GENAT) "\",")
    out("  \"captured_at\": \"" jesc(CAPAT) "\",")
    out("  \"host\": \"" jesc(HOST) "\",")
    out("  \"os_version\": \"" jesc(OSV) "\",")
    out("  \"arch\": \"" jesc(ARCH) "\",")
    out("  \"source_file\": \"" jesc(SRC) "\",")
    out("  \"sort_preset\": \"" jesc(SORTP) "\",")
    out("  \"null_as_empty\": " (NULLMODE == 1 ? "true" : "false") ",")

    # ---- 列清单 ----
    line = "  \"columns\": ["
    for (j = 1; j <= NC; j++) line = line (j == 1 ? "" : ", ") "\"" jesc(COL[j]) "\""
    out(line "],")

    # ---- 列元信息 ----
    out("  \"column_meta\": {")
    for (j = 1; j <= NC; j++) {
        c = COL[j]
        zh = ZH[c]; if (zh == "") zh = (substr(c, 1, 4) == "raw_" ? substr(c, 5) : c)
        gr = GRP[c]; if (gr == "") gr = (substr(c, 1, 4) == "raw_" ? "未预置字段" : "其它")
        out("    \"" jesc(c) "\": {\"zh\": \"" jesc(zh) "\", \"grp\": \"" jesc(gr) "\"}" (j == NC ? "" : ","))
    }
    out("  },")

    line = "  \"column_groups\": ["
    for (j = 1; j <= GRPN; j++) line = line (j == 1 ? "" : ", ") "\"" jesc(GRPORDER[j]) "\""
    out(line "],")

    line = "  \"list_columns\": ["
    k = 0
    for (j = 1; j <= NC; j++) if (COL[j] in LISTCOLS) { k++; line = line (k == 1 ? "" : ", ") "\"" jesc(COL[j]) "\"" }
    out(line "],")

    line = "  \"bool_columns\": ["
    k = 0
    for (j = 1; j <= NC; j++) if (COL[j] in BOOLCOLS) { k++; line = line (k == 1 ? "" : ", ") "\"" jesc(COL[j]) "\"" }
    out(line "],")

    # ---- 记录组 ----
    out("  \"sections\": [")
    sn = 0
    if (SECFILE != "") {
        while ((getline sl < SECFILE) > 0) {
            sn++
            if (sn == 1) continue                       # 表头
            kk = split(sl, F, "\t")
            if (k < 1) continue
            out("    {\"uid\": \"" jesc(F[1]) "\", \"group_uuid\": \"" jesc(F[2]) "\", " \
                "\"sm_migrated\": \"" jesc(F[3]) "\", \"ls_registered\": \"" jesc(F[4]) "\", " \
                "\"item_count\": " (F[5] + 0) ", \"source_line\": " (F[6] + 0) ", " \
                "\"extra\": \"" jesc(F[7]) "\"}" ("," ))
        }
        close(SECFILE)
    }
    # 去掉最后一行多余逗号：重建（简单可靠）
    if (sn > 1) {
        # OUT 里最后一条是 sections 项，追加一个占位后修正
        last = OUT[ON]
        sub(/,$/, "", last)
        OUT[ON] = last
    }
    out("  ],")

    # ---- 条目 ----
    out("  \"items\": [")
    for (i = 1; i <= ri; i++) {
        line = "    {"
        first = 1
        for (j = 1; j <= NC; j++) {
            c = COL[j]
            v = V[i, j]
            if (NULLMODE == 1 && v == "(null)") v = ""
            if (c in LISTCOLS) {
                if (v == "") s = "[]"
                else {
                    n2 = split(v, A, " \\| ")
                    s = "["
                    for (q = 1; q <= n2; q++) s = s (q == 1 ? "" : ", ") "\"" jesc(A[q]) "\""
                    s = s "]"
                }
            } else if (c in BOOLCOLS) {
                s = (v == "TRUE") ? "true" : "false"
            } else {
                s = "\"" jesc(v) "\""
            }
            line = line (first ? "" : ", ") "\"" jesc(c) "\": " s
            first = 0
        }
        out(line "}" (i == ri ? "" : ","))
    }
    out("  ]")
    out("}")

    for (i = 1; i <= ON; i++) print OUT[i]
}

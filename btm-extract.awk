# btm-extract.awk —— 把 `sudo sfltool dumpbtm` 的文本输出解析为「无损 TSV」
#
# 设计原则：
#   1. 一个字段不丢：预置字段映射为规范列；未预置的 key 自动成为 raw_<原字段名> 列。
#   2. 不去重：同一标识符的多条注册项原样保留，只用 dup_group 列标记。
#   3. 不改写原值："(null)"、"(0x10010)" 一律原样（-v nullmode=1 可清空）。
#   4. 排序可复现：所有排序口径都以 uuid + seq 收尾，两次导出可逐行 diff。
#
# 用法：
#   awk -v sort=scope -v hdrfile=H -v secfile=S -v nullmode=0 \
#       -f btm-extract.awk dumpbtm.txt
#   标准输出 = 「排序键 <TAB> 数据行」；再交给 sort 排序、cut 掉排序键。
#   表头写入 hdrfile，记录组元信息写入 secfile。

BEGIN {
    OFS = "\t"

    # ---------- 已知字段（其余自动 raw_ 前缀保留） ----------
    KNOWN["UUID"] = 1
    KNOWN["Name"] = 1
    KNOWN["Developer Name"] = 1
    KNOWN["Team Identifier"] = 1
    KNOWN["Type"] = 1
    KNOWN["Flags"] = 1
    KNOWN["Disposition"] = 1
    KNOWN["Identifier"] = 1
    KNOWN["URL"] = 1
    KNOWN["Executable Path"] = 1
    KNOWN["Generation"] = 1
    KNOWN["Bundle Identifier"] = 1
    KNOWN["Parent Identifier"] = 1
    KNOWN["Assoc. Bundle IDs"] = 1

    # ---------- 持久化机制 ----------
    MECH["daemon"] = 0
    MECH["agent"] = 1
    MECH["login item"] = 2
    MECH["app"] = 3
    MECH["quicklook"] = 4
    MECH["spotlight"] = 5
    MECH["developer"] = 6
    MECHZH["daemon"] = "开机即启动（系统级 root 守护进程）"
    MECHZH["agent"] = "登录后启动（当前用户代理）"
    MECHZH["login item"] = "登录后启动（登录项辅助程序）"
    MECHZH["app"] = "应用注册项"
    MECHZH["quicklook"] = "QuickLook 预览插件"
    MECHZH["spotlight"] = "Spotlight 导入插件"
    MECHZH["developer"] = "开发者父记录（本身不执行）"

    # ---------- Identifier 前缀数字 -> 作用域 ----------
    IDENTZH["2"] = "应用"
    IDENTZH["4"] = "登录项"
    IDENTZH["8"] = "用户代理"
    IDENTZH["16"] = "系统守护进程"
    IDENTZH["64"] = "Spotlight 插件"
    IDENTZH["2048"] = "QuickLook 插件"
    IDENTZH["4096"] = "系统扩展"

    # ---------- 输出列顺序 ----------
    # 注意：url_path 与 executable_path 后面紧跟的四个分类列必须在同一个地方维护 ——
    # 它们回答的是「配置放在哪 / 可执行文件落在哪」这两个**不同**的问题。
    split("uid uid_domain group_uuid sm_migrated ls_registered seq uuid name developer_name team_identifier type_raw type_mechanism type_modifiers type_hex flags_raw flags_list flags_hex disposition_raw disposition_hex enabled allowed visible notified hidden identifier identifier_scope identifier_scope_zh identifier_base url url_path config_kind config_dir executable_path exec_scope exec_dir bundle_identifier bundle_key parent_identifier parent_kind assoc_bundle_ids assoc_count embedded_item_identifiers embedded_count generation child_count depth node_path persistence_zh dup_group match_key source_line", CANON, " ")
    CANCN = 51

    if (SORT == "") SORT = "scope"
    if (NULLMODE == "") NULLMODE = 0

    n = 0          # 条目计数
    sec = 0        # 记录组计数
    cur = 0        # 当前条目（0 = 尚未进入条目区）
    inemb = 0      # 是否正在读「嵌入项」子列表

    # 控制字符表（JSON 转义用）
    for (c = 0; c < 32; c++) CT[sprintf("%c", c)] = sprintf("\\u%04x", c)
}

# ---------------------------------------------------------------- 主解析循环
{
    s = $0
    gsub(/\r$/, "", s)
    gsub(/\t/, " ", s)              # 制表符替换，避免破坏 TSV 结构

    t = s
    gsub(/^[ \t]+|[ \t]+$/, "", t)
    if (t == "") next
    if (t ~ /^=+$/) next

    # ---- 记录组标题 ----
    if (index(t, "Records for UID") == 1) {
        rest = substr(t, 16)
        gsub(/^[ \t]+/, "", rest)
        p = index(rest, ":")
        if (p == 0) {
            uidstr = rest; guuid = ""
        } else {
            uidstr = substr(rest, 1, p - 1)
            guuid = substr(rest, p + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", uidstr)
            gsub(/^[ \t]+|[ \t]+$/, "", guuid)
        }
        sec++
        s_uid[sec] = uidstr
        s_guuid[sec] = guuid
        s_line[sec] = NR
        s_mig[sec] = ""
        s_lsreg[sec] = ""
        s_count[sec] = 0
        s_extra[sec] = ""
        cur = 0
        inemb = 0
        next
    }

    if (sec == 0) next              # 文件头杂乱行

    # ---- 条目头 "#N:"（必须先于一切 key:value 判断）----
    if (t ~ /^#[0-9]+:$/) {
        n++
        r_sec[n] = sec
        r_seq[n] = substr(t, 2, length(t) - 2) + 0
        r_line[n] = NR
        s_count[sec]++
        cur = n
        inemb = 0
        next
    }

    # ---- 嵌入项子列表 "    #N: identifier" ----
    if (inemb && t ~ /^#[0-9]+:[ \t]+.+/) {
        p = index(t, ":")
        v2 = substr(t, p + 1); gsub(/^[ \t]+|[ \t]+$/, "", v2)
        embn[n]++
        emb[n, embn[n]] = v2
        next
    }

    # ---- 普通字段 "Key: value" ----
    p = index(t, ":")
    if (p == 0) next
    k = substr(t, 1, p - 1); gsub(/[ \t]+$/, "", k)
    val = substr(t, p + 1); gsub(/^[ \t]+|[ \t]+$/, "", val)

    if (k == "Indentifier") k = "Identifier"    # sfltool 历史上的拼写错误

    inemb = 0

    # ---- 记录组级（条目区之前）----
    if (cur == 0) {
        if (k == "ServiceManagement migrated") { s_mig[sec] = val; next }
        if (k == "LaunchServices registered") { s_lsreg[sec] = val; next }
        if (k == "Items") next
        s_extra[sec] = s_extra[sec] (s_extra[sec] == "" ? "" : " ; ") k "=" val
        next
    }

    if (k == "Embedded Item Identifiers") {
        if (val != "") {
            embn[n]++
            emb[n, embn[n]] = val
        }
        inemb = 1
        next
    }

    if (!((n, k) in kseen)) {
        kseen[n, k] = 1
        kc[n]++
        kv[n, kc[n]] = k
    }
    v[n, k] = val
}

# ---------------------------------------------------------------- 工具函数
function RV(i, key) { return ((i, key) in v) ? v[i, key] : "" }

function trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }

function domain_rank(u,   x) {
    x = u + 0
    if (substr(u, 1, 1) == "-") return 0
    if (x == 0) return 1
    return 2
}

function domain_name(u,   x) {
    x = u + 0
    if (substr(u, 1, 1) == "-") return "system"
    if (x == 0) return "root"
    return "user"
}

function domain_zh(u,   x) {
    x = u + 0
    if (substr(u, 1, 1) == "-") return "系统合成组（UID -2）"
    if (x == 0) return "root（UID 0）"
    return "普通用户（UID " u "）"
}

# 解析 Type："legacy daemon (0x10010)" -> 全局 TYPE_MECH / TYPE_MODS / TYPE_HEX
function split_type(raw,   text, k, words, q, mods) {
    text = raw
    TYPE_HEX = ""
    if (match(text, /\(0x[0-9a-fA-F]+\)/)) {
        TYPE_HEX = substr(text, RSTART + 1, RLENGTH - 2)
        text = substr(text, 1, RSTART - 1) " " substr(text, RSTART + RLENGTH)
    } else if (match(text, /\([0-9a-fA-F]+\)/)) {
        TYPE_HEX = substr(text, RSTART + 1, RLENGTH - 2)
        text = substr(text, 1, RSTART - 1) " " substr(text, RSTART + RLENGTH)
    }
    gsub(/^[ \t]+|[ \t]+$/, "", text)
    gsub(/[ \t][ \t]+/, " ", text)
    k = split(text, words, " ")
    TYPE_MECH = ""; TYPE_MODS = ""
    if (k == 0) return
    if (k >= 2 && words[k] == "item" && words[k - 1] == "login") {
        TYPE_MECH = "login item"
        for (q = 1; q <= k - 2; q++) TYPE_MODS = TYPE_MODS (TYPE_MODS == "" ? "" : " | ") words[q]
    } else {
        TYPE_MECH = words[k]
        for (q = 1; q < k; q++) TYPE_MODS = TYPE_MODS (TYPE_MODS == "" ? "" : " | ") words[q]
    }
}

# 解析 "[ a, b ] (0x5)" -> 全局 BL[1..BLN] / BHEX
function parse_bracket(raw,   txt, p, q, i) {
    BLN = 0; BHEX = ""
    txt = raw
    p = index(txt, "[")
    q = index(txt, "]")
    if (p > 0 && q > p) {
        mid = substr(txt, p + 1, q - p - 1)
        gsub(/^[ \t]+|[ \t]+$/, "", mid)
        if (mid != "") {
            BLN = split(mid, BL, /,[ \t]*/)
            for (i = 1; i <= BLN; i++) gsub(/^[ \t]+|[ \t]+$/, "", BL[i])
        }
        txt = substr(txt, q + 1)
    }
    if (match(txt, /\(0x[0-9a-fA-F]+\)/)) BHEX = substr(txt, RSTART + 1, RLENGTH - 2)
    else if (match(txt, /\([0-9a-fA-F]+\)/)) BHEX = substr(txt, RSTART + 1, RLENGTH - 2)
}

# 逗号分隔（无方括号时的兜底） -> 全局 BL / BLN
function parse_csv_list(raw,   i, tmp) {
    BLN = 0
    tmp = raw
    gsub(/^\[|\]$/, "", tmp)
    gsub(/^[ \t]+|[ \t]+$/, "", tmp)
    if (tmp == "" || tmp == "(null)") return
    BLN = split(tmp, BL, ",")
    for (i = 1; i <= BLN; i++) gsub(/^[ \t]+|[ \t]+$/, "", BL[i])
}

function put(i, f, val) { row[i, f] = val; PRESENT[f] = 1 }

# 取目录部分（去掉最后一段）。保留原路径的绝对/相对性质；无斜杠返回空。
function dirname_of(p,   q, h) {
    if (p == "") return ""
    q = length(p)
    while (q > 1 && substr(p, q, 1) != "/") q--
    if (q <= 1) return (substr(p, 1, 1) == "/" ? "/" : "")
    return substr(p, 1, q - 1)
}

# 「配置（plist / bundle）放在哪里」—— 依据 URL。顺序即优先级，先匹配者胜。
function config_kind_of(p,   s) {
    if (p == "") return "无配置路径"
    s = p
    if (s ~ /^\.\//) s = substr(s, 3)            # 归一化 ./Contents/... 这种写法
    if (index(s, "/Library/LaunchDaemons/") == 1)     return "系统守护进程配置"
    if (index(s, "/Library/LaunchAgents/") == 1)      return "全局代理配置"
    if (s ~ /^\/Users\/[^\/]+\/Library\/LaunchAgents\//) return "用户代理配置"
    if (index(s, "/System/Library/") == 1)            return "系统内置配置"
    # 「出现在路径中间的 /Contents/」说明它落在某个应用包**内部**（登录项 helper、
    # Spotlight 导入器、QuickLook 扩展都是这个形态），优先于「应用包自身」判定。
    if (s ~ /(^|\/)Contents\//)                       return "应用包内嵌组件"
    if (s ~ /\.app\/?$/)                              return "应用包自身"
    if (substr(s, 1, 1) == "/")                       return "其它绝对路径"
    return "其它相对路径"
}

# 「配置所属目录」：树的分组依据，也是表格里「配置具体在哪」那一列。
# 若该路径本身就是 .app 包，则上溯到它所在目录 —— 否则 /Applications 下几十个
# 应用会各自变成一个只含 1 条的假分组，读起来是列表而不是树。
function config_dir_of(p,   d) {
    d = dirname_of(p)
    if (d ~ /\.app$/) d = dirname_of(d)
    return d
}

# 「独立可执行文件落在哪里」—— 依据 Executable Path。与配置分类完全不共用判断。
function exec_scope_of(p,   s) {
    if (p == "") return "无独立可执行文件"
    s = p
    if (s ~ /^\.\//) s = substr(s, 3)
    if (s ~ /^\/Applications\/[^\/]+\.app\/Contents\/MacOS\//) return "应用包内（Contents/MacOS）"
    if (index(s, "/Library/PrivilegedHelperTools/") == 1)      return "系统特权 Helper"
    if (index(s, "/Library/Application Support/") == 1)        return "系统应用支持目录"
    if (index(s, "/System/Library/") == 1)                     return "系统内置"
    if (index(s, "/Library/") == 1)                            return "系统库其它位置"
    if (s ~ /^\/Users\//)                                      return "用户主目录（用户可写）"
    if (index(s, "/usr/local/") == 1)                          return "本地安装目录（/usr/local）"
    if (s ~ /\.app(\/|$)/)                                     return "应用包内（其它）"
    if (substr(s, 1, 1) != "/")                                return "相对路径"
    return "其它绝对路径"
}

# ---------------------------------------------------------------- 派生 + 输出
END {
    # ============ 1. 逐条派生 ============
    for (i = 1; i <= n; i++) {
        u = s_uid[r_sec[i]]
        r_uid[i] = u
        put(i, "uid", u)
        put(i, "uid_domain", domain_name(u))
        put(i, "group_uuid", s_guuid[r_sec[i]])
        put(i, "sm_migrated", s_mig[r_sec[i]])
        put(i, "ls_registered", s_lsreg[r_sec[i]])
        put(i, "seq", r_seq[i])
        put(i, "uuid", RV(i, "UUID"))
        put(i, "name", RV(i, "Name"))
        put(i, "developer_name", RV(i, "Developer Name"))
        put(i, "team_identifier", RV(i, "Team Identifier"))

        # --- 类型 ---
        traw = RV(i, "Type")
        put(i, "type_raw", traw)
        split_type(traw)
        r_mech[i] = TYPE_MECH
        put(i, "type_mechanism", TYPE_MECH)
        put(i, "type_modifiers", TYPE_MODS)
        put(i, "type_hex", TYPE_HEX)

        # --- 标志 ---
        fraw = RV(i, "Flags")
        put(i, "flags_raw", fraw)
        parse_bracket(fraw)
        fl = ""
        for (q = 1; q <= BLN; q++) fl = fl (fl == "" ? "" : " | ") BL[q]
        put(i, "flags_list", fl)
        put(i, "flags_hex", BHEX)

        # --- 处置状态 ---
        draw = RV(i, "Disposition")
        put(i, "disposition_raw", draw)
        parse_bracket(draw)
        dl = ""
        on["enabled"] = 0; on["allowed"] = 0; on["visible"] = 0
        on["notified"] = 0; on["disabled"] = 0
        for (q = 1; q <= BLN; q++) {
            dl = dl (dl == "" ? "" : " | ") BL[q]
            on[BL[q]] = 1
        }
        put(i, "disposition_hex", BHEX)
        put(i, "enabled", on["enabled"] ? "TRUE" : "FALSE")
        put(i, "allowed", on["allowed"] ? "TRUE" : "FALSE")
        put(i, "visible", on["visible"] ? "TRUE" : "FALSE")
        put(i, "notified", on["notified"] ? "TRUE" : "FALSE")
        put(i, "hidden", on["visible"] ? "FALSE" : "TRUE")

        # --- 标识符 ---
        idv = RV(i, "Identifier")
        put(i, "identifier", idv)
        if (match(idv, /^[0-9]+\./)) {
            sc = substr(idv, 1, RLENGTH - 1)
            ib = substr(idv, RLENGTH + 1)
            put(i, "identifier_scope", sc)
            put(i, "identifier_scope_zh", IDENTZH[sc])
        } else {
            ib = idv
            put(i, "identifier_scope", "")
            put(i, "identifier_scope_zh", (idv == "" || idv == "(null)") ? "" : "开发者父记录")
        }
        put(i, "identifier_base", ib)
        r_ident[i] = idv
        r_ibase[i] = ib

        # --- 配置路径：URL 指向的 plist / bundle / plist 内部组件 ---
        # 语义纪律（之前这里是有问题的）：本列**只表示配置落点**。
        # 旧实现在 URL 为空时用 Executable Path 顶替，等于让同一列随记录改变含义
        # （配置归配置、可执行归可执行），必须分开。URL 为空就留空/留 (null)。
        ul = RV(i, "URL")
        put(i, "url", ul)
        up = ul
        if (index(up, "file://") == 1) up = substr(up, 8)
        gsub(/%20/, " ", up)
        gsub(/%2F/, "/", up)
        gsub(/%40/, "@", up)
        put(i, "url_path", up)

        # 分类时把 (null) 当「没有」处理，但列里仍按本项目惯例原样保留 (null)（清空交给 --null-as-empty）
        cfgv = (up == "(null)") ? "" : up
        put(i, "config_kind", config_kind_of(cfgv))
        put(i, "config_dir",  config_dir_of(cfgv))

        # --- 可执行文件落点：独立的一列、独立的分类，不与上面的配置分类混用 ---
        ep = RV(i, "Executable Path")
        put(i, "executable_path", ep)
        execv = (ep == "(null)") ? "" : ep
        put(i, "exec_scope", exec_scope_of(execv))
        put(i, "exec_dir",   dirname_of(execv))

        # --- 关联 Bundle（先算，归组键要用它的第一个值）---
        raw = RV(i, "Assoc. Bundle IDs")
        put(i, "assoc_bundle_ids", "")
        ac = 0
        al = ""
        assoc1 = ""
        if (raw != "" && raw != "(null)") {
            parse_bracket(raw)
            if (BLN == 0) parse_csv_list(raw)
            for (q = 1; q <= BLN; q++) {
                al = al (al == "" ? "" : " | ") BL[q]
                ac++
                if (q == 1) assoc1 = BL[q]
            }
            put(i, "assoc_bundle_ids", al)
        }
        put(i, "assoc_count", ac)

        # --- Bundle ---
        bid = RV(i, "Bundle Identifier")
        if (bid == "") bid = "(null)"
        put(i, "bundle_identifier", bid)

        # Bundle 归组键：优先自身 Bundle ID，其次第一个 Assoc. Bundle ID。
        # 不用「标识符基名」兜底 —— 那会把开发者和代理拆成一堆只含 1 条的假分组。
        bkey = ""
        if (bid != "(null)" && bid != "") bkey = bid
        else if (assoc1 != "" && assoc1 != "(null)") bkey = assoc1
        put(i, "bundle_key", bkey)

        # --- 父 ---
        pv = RV(i, "Parent Identifier")
        if (pv == "") pv = "(null)"
        put(i, "parent_identifier", pv)
        r_parent[i] = pv
        if (pv == "(null)") put(i, "parent_kind", "无父记录（顶层）")
        else if (match(pv, /^[0-9]+\./)) put(i, "parent_kind", "应用 / 条目记录")
        else put(i, "parent_kind", "开发者记录")

        # --- 嵌入项 ---
        el = ""
        for (q = 1; q <= embn[i]; q++) el = el (el == "" ? "" : " | ") emb[i, q]
        put(i, "embedded_item_identifiers", el)
        put(i, "embedded_count", embn[i])

        # --- 代数 ---
        gv = RV(i, "Generation")
        put(i, "generation", (gv == "" ? "(null)" : gv))

        # --- 人话 ---
        put(i, "persistence_zh", MECHZH[TYPE_MECH])

        # --- 语义主键 ---
        mk = ib "|" r_mech[i]
        r_mk[i] = mk
        put(i, "match_key", mk)

        # --- 展示名 ---
        nm = RV(i, "Name")
        disp[i] = (nm == "" || nm == "(null)") ? ib : nm
        if (disp[i] == "") disp[i] = "(未命名)"

        # --- 未预置字段 -> raw_<原字段名> ---
        for (q = 1; q <= kc[i]; q++) {
            kk2 = kv[i, q]
            if (!(kk2 in KNOWN)) put(i, "raw_" kk2, v[i, kk2])
        }
    }

    # ============ 2. 重复注册标记（按文件顺序编号，保证可复现） ============
    for (i = 1; i <= n; i++) {
        if (r_mk[i] == "|" || r_mk[i] == "") continue
        kk = r_uid[i] SUBSEP r_mk[i]
        DUPN[kk]++
    }
    gid = 0
    for (i = 1; i <= n; i++) {
        if (r_mk[i] == "|" || r_mk[i] == "") continue
        kk = r_uid[i] SUBSEP r_mk[i]
        if (DUPN[kk] > 1) {
            if (!(kk in DUPG)) { gid++; DUPG[kk] = "D" sprintf("%02d", gid) }
            put(i, "dup_group", DUPG[kk])
        } else put(i, "dup_group", "")
    }

    # ============ 3. 归属树（父记录索引、子项数、层级、归属链） ============
    for (p = 1; p <= n; p++) {
        if (r_ident[p] == "") continue
        IDX[r_uid[p] SUBSEP r_ident[p]] = p
        if (!(r_ident[p] in IDXANY)) IDXANY[r_ident[p]] = p
    }
    for (i = 1; i <= n; i++) {
        pv = r_parent[i]
        par[i] = 0
        if (pv == "(null)" || pv == "") continue
        kk = r_uid[i] SUBSEP pv
        if (kk in IDX) { par[i] = IDX[kk]; cc[IDX[kk]]++ }
        else if (pv in IDXANY) { par[i] = -IDXANY[pv]; cc[IDXANY[pv]]++ }
    }
    for (i = 1; i <= n; i++) {
        put(i, "child_count", (i in cc) ? cc[i] : 0)

        d = 0; j = i; guard = 0
        while (par[j] != 0 && guard < 40) {
            j = (par[j] < 0) ? -par[j] : par[j]
            d++; guard++
            if (j == i) break
        }
        put(i, "depth", d)

        chain = ""; j = i; guard = 0
        while (par[j] != 0 && guard < 12) {
            jj = (par[j] < 0) ? -par[j] : par[j]
            chain = disp[jj] " > " chain
            j = jj; guard++
            if (j == i) break
        }
        put(i, "node_path", chain disp[i])

        put(i, "source_line", r_line[i])
    }

    # ============ 4. 列清单 ============
    NC = 0
    for (q = 1; q <= CANCN; q++) { NC++; COL[NC] = CANON[q] }
    exn = 0
    for (f in PRESENT) {
        if (substr(f, 1, 4) == "raw_") { exn++; EX[exn] = f }
    }
    # 冒泡排序（额外列很少，稳定可复现）
    for (a = 1; a < exn; a++)
        for (b = 1; b <= exn - a; b++)
            if (EX[b] > EX[b + 1]) { tmp = EX[b]; EX[b] = EX[b + 1]; EX[b + 1] = tmp }
    for (a = 1; a <= exn; a++) { NC++; COL[NC] = EX[a] }

    # ============ 5. 表头 + 记录组元信息 ============
    hdr = ""
    for (q = 1; q <= NC; q++) hdr = hdr (q == 1 ? "" : "\t") COL[q]
    print hdr > HDRFILE
    close(HDRFILE)

    if (SECFILE != "") {
        print "uid\tgroup_uuid\tsm_migrated\tls_registered\titem_count\tsource_line\textra" > SECFILE
        for (a = 1; a <= sec; a++)
            print s_uid[a], s_guuid[a], s_mig[a], s_lsreg[a], s_count[a], s_line[a], s_extra[a] > SECFILE
        close(SECFILE)
    }

    # ============ 6. 排序 + 输出 ============
    for (i = 1; i <= n; i++) {
        d = domain_rank(r_uid[i])
        m = MECH[r_mech[i]]; if (m == "") m = 9
        ib2 = tolower(r_ibase[i])
        nm2 = tolower(disp[i])
        dv2 = tolower(RV(i, "Developer Name"))

        if (SORT == "file")        k = sprintf("%s %06d %08d", r_uid[i] + 0, r_sec[i], r_seq[i])
        else if (SORT == "type")   k = sprintf("%d %d %s", m, d, ib2)
        else if (SORT == "vendor") k = dv2 " " nm2 " " d
        else if (SORT == "identifier") k = ib2 " " d " " m
        else if (SORT == "name")   k = nm2 " " d
        else if (SORT == "status") k = sprintf("%d %d %d %s", (on["enabled"] ? 0 : 1), d, m, ib2)
        else                       k = sprintf("%d %d %s", d, m, ib2)

        line = ""
        for (q = 1; q <= NC; q++) {
            val = ((i, COL[q]) in row) ? row[i, COL[q]] : ""
            if (NULLMODE == 1 && val == "(null)") val = ""
            gsub(/\t/, " ", val)
            line = line (q == 1 ? "" : "\t") val
        }
        # 排序键 + 兜底 tie-break（uuid、seq）
        sk = k " " RV(i, "UUID") " " sprintf("%08d", r_seq[i]) " " r_sec[i]
        print sk "\t" line
    }
}

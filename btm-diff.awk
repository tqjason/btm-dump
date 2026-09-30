# btm-diff.awk —— 比较两个快照的无损 TSV，输出「新增 / 移除 / 属性变化 / 派生变化 / 仅代数变化」
#
# 三级匹配（依次尝试，逐级放宽），保证同一项即使换了 UUID 重新注册也能认出来：
#   ① uid + uuid
#   ② uid + match_key（标识符基名｜持久化机制）
#   ③ uid + match_key + executable_path
#
# 用法：
#   awk -v MAP=colmap.tsv -v MDFILE=changes.md -v CSVFILE=changes.csv \
#       -v BASEDIR=... -v NEWDIR=... -v BASEAT=... -v NEWAT=... \
#       -f btm-diff.awk base/btm_items.tsv new/btm_items.tsv

BEGIN {
    FS = "\t"; OFS = "\t"

    # 纯记账列，不参与比对
    SKIPC["seq"] = 1
    SKIPC["source_line"] = 1
    SKIPC["match_key"] = 1

    # 派生/结构类（会跟着关系变化而变，单独一层，避免淹没核心改动）
    T2["child_count"] = 1
    T2["depth"] = 1
    T2["node_path"] = 1
    T2["dup_group"] = 1

    # 计数类：每次重新加载都可能自己变，单独一层
    T3["generation"] = 1

    if (MAP != "") {
        while ((getline l < MAP) > 0) {
            q = split(l, F, "\t")
            if (q >= 2) ZH[F[1]] = F[2]
        }
        close(MAP)
    }
    if (MAXMD == "") MAXMD = 300
}

# ---------------------------------------------------------------- 读基线
#
# 【重要】两个快照的列集合**可能不同**：新增字段、macOS 升级多出 raw_* 列、
# 一边用了 -n 清空 (null) …… 都可能让列数变化。
# 所以绝不能拿第一份文件的表头去当两边的列清单 —— 那会让第二份文件里
# 从差异点往后的所有列整体错位，并且**静默**产出满屏假改动。
# 做法：按列名对齐。以基线的列序为基准，新快照独有的列追加到末尾；
# 只在一边存在的列不参与逐条比对，而是单独报成「字段集合变化」。
NR == FNR {
    if (FNR == 1) {
        BC = NF
        for (c = 1; c <= BC; c++) {
            COL[c] = $c
            INB[$c] = 1
            if ($c == "uid")               IU  = c
            else if ($c == "uuid")         IUU = c
            else if ($c == "match_key")    IMK = c
            else if ($c == "executable_path") IEX = c
            else if ($c == "name")         INM = c
            else if ($c == "identifier_base") IIB = c
            else if ($c == "identifier")   IID = c
            else if ($c == "type_mechanism") IME = c
            else if ($c == "enabled")      IEN = c
        }
        NC = BC
        next
    }
    bi++
    for (c = 1; c <= BC; c++) BV[bi, c] = $c
    next
}

# ---------------------------------------------------------------- 读新快照
{
    if (FNR == 1) {
        NNC = NF
        for (c = 1; c <= NNC; c++) {
            NIDX[$c] = c
            if (!($c in INB)) { NC++; COL[NC] = $c; nONLYN++; ONLYN[nONLYN] = $c }
        }
        # 基线有、新快照没有的列
        for (c = 1; c <= BC; c++) {
            if (COL[c] in NIDX) BOTH[COL[c]] = 1
            else { nONLYB++; ONLYB[nONLYB] = COL[c] }
        }
        # 参与匹配与展示的核心列，两边必须都有
        split("uid uuid match_key executable_path name identifier_base identifier type_mechanism enabled", CORE, " ")
        for (c = 1; c <= 9; c++) if (!(CORE[c] in NIDX)) { nMISS++; MISS[nMISS] = CORE[c] }
        next
    }
    ni++
    for (c = 1; c <= NC; c++) {
        nm = COL[c]
        p = (nm in NIDX) ? NIDX[nm] : ""
        NV[ni, c] = (p == "") ? "" : $p
    }
}

# ---------------------------------------------------------------- 工具
function rowname(A, i,   v) {
    v = A[i, INM]
    if (v == "" || v == "(null)") v = A[i, IIB]
    if (v == "" || v == "(null)") v = A[i, IID]
    if (v == "" || v == "(null)") v = "(未命名)"
    return v
}
function rowname_esc(A, i) { return md(rowname(A, i)) }

function md(s,   t) {
    t = s
    gsub(/\|/, "\\|", t)
    gsub(/\r?\n/, " ", t)
    if (t == "") return "*(空)*"
    if (length(t) > 160) t = substr(t, 1, 157) "..."
    return "`" t "`"
}
function csvq(s,   t) {
    t = s
    if (t == "") t = ""
    gsub(/"/, "\"\"", t)
    return "\"" t "\""
}
function field_zh(c) { return (c in ZH) ? ZH[c] : c }

# ---------------------------------------------------------------- 主流程
END {
    if (bi == 0 && ni == 0) { print "两个快照都是空的，无可比较。"; exit }

    for (i = 1; i <= bi; i++) {
        u = BV[i, IU]
        B1[u "|" BV[i, IUU]] = i
        B2[u "|" BV[i, IMK]] = i
        B3[u "|" BV[i, IMK] "|" BV[i, IEX]] = i
    }
    for (j = 1; j <= ni; j++) {
        u = NV[j, IU]
        N1[u "|" NV[j, IUU]] = j
        N2[u "|" NV[j, IMK]] = j
        N3[u "|" NV[j, IMK] "|" NV[j, IEX]] = j
    }

    nadd = 0; nrem = 0; nchg = 0; nT2 = 0; nT3 = 0; nrowchg = 0; nrowT2 = 0; nrowT3 = 0

    for (i = 1; i <= bi; i++) {
        u = BV[i, IU]
        j = 0; how = ""
        if ((u "|" BV[i, IUU]) in N1) { j = N1[u "|" BV[i, IUU]]; how = "UUID" }
        else if ((u "|" BV[i, IMK]) in N2) { j = N2[u "|" BV[i, IMK]]; how = "标识符+机制" }
        else if ((u "|" BV[i, IMK] "|" BV[i, IEX]) in N3) { j = N3[u "|" BV[i, IMK] "|" BV[i, IEX]]; how = "标识符+机制+路径" }

        if (j == 0) { nrem++; REM[nrem] = i; continue }

        NM[j] = 1; MATCHHOW[i] = how
        r1 = 0; r2 = 0; r3 = 0
        for (c = 1; c <= NC; c++) {
            col = COL[c]
            if (col in SKIPC) continue
            if (!(col in BOTH)) continue        # 只在一边存在的列，归入「字段集合变化」，不逐条报
            ov = BV[i, c]; nv = NV[j, c]
            if (ov == nv) continue
            if (col in T3) {
                nT3++; T3R[nT3, "i"] = i; T3R[nT3, "j"] = j; T3R[nT3, "c"] = col
                T3R[nT3, "ov"] = ov; T3R[nT3, "nv"] = nv; r3++
            } else if (col in T2) {
                nT2++; T2R[nT2, "i"] = i; T2R[nT2, "j"] = j; T2R[nT2, "c"] = col
                T2R[nT2, "ov"] = ov; T2R[nT2, "nv"] = nv; r2++
            } else {
                nchg++; CHGR[nchg, "i"] = i; CHGR[nchg, "j"] = j; CHGR[nchg, "c"] = col
                CHGR[nchg, "ov"] = ov; CHGR[nchg, "nv"] = nv; r1++
            }
        }
        if (r1) nrowchg++
        if (r2) nrowT2++
        if (r3) nrowT3++
    }

    for (j = 1; j <= ni; j++) if (!(j in NM)) { nadd++; ADD[nadd] = j }

    # ------------------------------------------------------------ CSV
    print "类型,UID,名称,标识符,持久化机制,字段,字段中文名,旧值,新值" > CSVFILE
    for (a = 1; a <= nadd; a++) {
        j = ADD[a]
        print "新增" "," csvq(NV[j, IU]) "," csvq(rowname(NV, j)) "," csvq(NV[j, IID]) "," \
              csvq(NV[j, IME]) ",,,," > CSVFILE
    }
    for (a = 1; a <= nrem; a++) {
        i = REM[a]
        print "移除" "," csvq(BV[i, IU]) "," csvq(rowname(BV, i)) "," csvq(BV[i, IID]) "," \
              csvq(BV[i, IME]) ",,,," > CSVFILE
    }
    for (a = 1; a <= nchg; a++)
        print "属性变化" "," csvq(BV[CHGR[a, "i"], IU]) "," csvq(rowname(BV, CHGR[a, "i"])) "," \
              csvq(BV[CHGR[a, "i"], IID]) "," csvq(BV[CHGR[a, "i"], IME]) "," csvq(CHGR[a, "c"]) "," \
              csvq(field_zh(CHGR[a, "c"])) "," csvq(CHGR[a, "ov"]) "," csvq(CHGR[a, "nv"]) > CSVFILE
    for (a = 1; a <= nT2; a++)
        print "派生变化" "," csvq(BV[T2R[a, "i"], IU]) "," csvq(rowname(BV, T2R[a, "i"])) "," \
              csvq(BV[T2R[a, "i"], IID]) "," csvq(BV[T2R[a, "i"], IME]) "," csvq(T2R[a, "c"]) "," \
              csvq(field_zh(T2R[a, "c"])) "," csvq(T2R[a, "ov"]) "," csvq(T2R[a, "nv"]) > CSVFILE
    for (a = 1; a <= nT3; a++)
        print "仅代数变化" "," csvq(BV[T3R[a, "i"], IU]) "," csvq(rowname(BV, T3R[a, "i"])) "," \
              csvq(BV[T3R[a, "i"], IID]) "," csvq(BV[T3R[a, "i"], IME]) "," csvq(T3R[a, "c"]) "," \
              csvq(field_zh(T3R[a, "c"])) "," csvq(T3R[a, "ov"]) "," csvq(T3R[a, "nv"]) > CSVFILE
    close(CSVFILE)

    # ------------------------------------------------------------ Markdown
    print "# 后台项快照比较报告" > MDFILE
    print "" > MDFILE
    print "- **基线**：`" BASEDIR "`　" BASEAT "　" bi " 条" > MDFILE
    print "- **对比**：`" NEWDIR "`　" NEWAT "　" ni " 条" > MDFILE
    print "- **匹配方式**：① uid+uuid → ② uid+标识符基名+机制 → ③ 再加可执行路径" > MDFILE
    print "- **不参与比对**：`seq`、`source_line`、`match_key`（纯记账）；`generation` 单列一层" > MDFILE
    print "" > MDFILE

    print "## 摘要" > MDFILE
    print "" > MDFILE
    print "| 类别 | 处数 | 涉及条目 |" > MDFILE
    print "|---|---:|---:|" > MDFILE
    print "| 新增 | " nadd " | " nadd " |" > MDFILE
    print "| 移除 | " nrem " | " nrem " |" > MDFILE
    print "| 属性变化（核心字段） | " nchg " | " nrowchg " |" > MDFILE
    print "| 派生变化（结构 / 标记） | " nT2 " | " nrowT2 " |" > MDFILE
    print "| 仅代数变化（Generation） | " nT3 " | " nrowT3 " |" > MDFILE
    print "" > MDFILE

    # 字段集合变化（只在一边存在的列，不参与逐条比对）
    if (nONLYN + nONLYB + nMISS > 0) {
        print "## 〇、字段集合变化（不参与逐条比对）" > MDFILE
        print "" > MDFILE
        print "两个快照的列集合不一致，下面这些列只在一边出现。它们**不会被算成逐条改动**，" > MDFILE
        print "但会解释为什么两侧的列数不同 —— 通常是解析器加了派生列、或 macOS 升级后多出了 raw_* 列。" > MDFILE
        print "" > MDFILE
        print "| 情况 | 字段 | 中文名 |" > MDFILE
        print "|---|---|---|" > MDFILE
        for (a = 1; a <= nONLYN; a++)
            print "| 仅新快照有（新增列） | `" ONLYN[a] "` | " field_zh(ONLYN[a]) " |" > MDFILE
        for (a = 1; a <= nONLYB; a++)
            print "| 仅基线有（已移除） | `" ONLYB[a] "` | " field_zh(ONLYB[a]) " |" > MDFILE
        for (a = 1; a <= nMISS; a++)
            print "| **新快照缺核心列**（匹配可能失真） | `" MISS[a] "` | " field_zh(MISS[a]) " |" > MDFILE
        print "" > MDFILE
    }

    # 新增
    print "## 一、新增（" nadd " 条）" > MDFILE
    print "" > MDFILE
    if (nadd == 0) print "无。" > MDFILE
    else {
        print "| UID | 名称 | 标识符 | 机制 | 启用 | 落点 |" > MDFILE
        print "|---|---|---|---|---|---|" > MDFILE
        for (a = 1; a <= nadd && a <= MAXMD; a++) {
            j = ADD[a]
            print "| " NV[j, IU] " | " rowname_esc(NV, j) " | " md(NV[j, IID]) " | " NV[j, IME] \
                  " | " NV[j, IEN] " | " md(NV[j, IEX]) " |" > MDFILE
        }
        if (nadd > MAXMD) print "\n> 仅显示前 " MAXMD " 条，完整清单见 changes.csv。" > MDFILE
    }
    print "" > MDFILE

    # 移除
    print "## 二、移除（" nrem " 条）" > MDFILE
    print "" > MDFILE
    if (nrem == 0) print "无。" > MDFILE
    else {
        print "| UID | 名称 | 标识符 | 机制 | 启用 | 落点 |" > MDFILE
        print "|---|---|---|---|---|---|" > MDFILE
        for (a = 1; a <= nrem && a <= MAXMD; a++) {
            i = REM[a]
            print "| " BV[i, IU] " | " rowname_esc(BV, i) " | " md(BV[i, IID]) " | " BV[i, IME] \
                  " | " BV[i, IEN] " | " md(BV[i, IEX]) " |" > MDFILE
        }
        if (nrem > MAXMD) print "\n> 仅显示前 " MAXMD " 条，完整清单见 changes.csv。" > MDFILE
    }
    print "" > MDFILE

    # 属性变化
    print "## 三、属性变化 —— 核心字段（" nchg " 处，涉及 " nrowchg " 条）" > MDFILE
    print "" > MDFILE
    if (nchg == 0) print "无。" > MDFILE
    else {
        print "| UID | 名称 | 标识符 | 字段 | 中文名 | 旧值 | 新值 |" > MDFILE
        print "|---|---|---|---|---|---|---|" > MDFILE
        for (a = 1; a <= nchg && a <= MAXMD; a++) {
            i = CHGR[a, "i"]
            print "| " BV[i, IU] " | " rowname_esc(BV, i) " | " md(BV[i, IID]) " | `" CHGR[a, "c"] \
                  "` | " field_zh(CHGR[a, "c"]) " | " md(CHGR[a, "ov"]) " | " md(CHGR[a, "nv"]) " |" > MDFILE
        }
        if (nchg > MAXMD) print "\n> 仅显示前 " MAXMD " 条，完整清单见 changes.csv。" > MDFILE
    }
    print "" > MDFILE

    # 派生变化
    print "## 四、派生变化 —— 结构 / 标记（" nT2 " 处，涉及 " nrowT2 " 条）" > MDFILE
    print "" > MDFILE
    if (nT2 == 0) print "无。" > MDFILE
    else {
        print "这层收到的是 `child_count`（子项数）、`depth`（层级）、`node_path`（归属链）、`dup_group`（重复注册组）。" > MDFILE
        print "它们本身不是原始字段，而是关系的投影 —— 变了通常说明有一条记录改了父级，或有新的重复注册出现。" > MDFILE
        print "" > MDFILE
        print "| UID | 名称 | 标识符 | 字段 | 中文名 | 旧值 | 新值 |" > MDFILE
        print "|---|---|---|---|---|---|---|" > MDFILE
        for (a = 1; a <= nT2 && a <= MAXMD; a++) {
            i = T2R[a, "i"]
            print "| " BV[i, IU] " | " rowname_esc(BV, i) " | " md(BV[i, IID]) " | `" T2R[a, "c"] \
                  "` | " field_zh(T2R[a, "c"]) " | " md(T2R[a, "ov"]) " | " md(T2R[a, "nv"]) " |" > MDFILE
        }
        if (nT2 > MAXMD) print "\n> 仅显示前 " MAXMD " 条，完整清单见 changes.csv。" > MDFILE
    }
    print "" > MDFILE

    # 仅代数变化
    print "## 五、仅代数变化 —— Generation（" nT3 " 处，涉及 " nrowT3 " 条）" > MDFILE
    print "" > MDFILE
    if (nT3 == 0) print "无。" > MDFILE
    else {
        print "`Generation` 是 BTM 自己的计数器，会随记录被重新注册而自增，**不代表你做了什么改动**。" > MDFILE
        print "单列这一层，就是为了不让它把上面第三层的真实改动冲淡。列在这里的条目，若同时出现在第三层，那才需要看。" > MDFILE
        print "" > MDFILE
        print "| UID | 名称 | 标识符 | 旧值 | 新值 |" > MDFILE
        print "|---|---|---|---|---|" > MDFILE
        for (a = 1; a <= nT3 && a <= MAXMD; a++) {
            i = T3R[a, "i"]
            print "| " BV[i, IU] " | " rowname_esc(BV, i) " | " md(BV[i, IID]) " | " T3R[a, "ov"] \
                  " | " T3R[a, "nv"] " |" > MDFILE
        }
        if (nT3 > MAXMD) print "\n> 仅显示前 " MAXMD " 条，完整清单见 changes.csv。" > MDFILE
    }
    close(MDFILE)

    # ------------------------------------------------------------ 终端摘要
    print "基线 " bi " 条　→　对比 " ni " 条"
    print "  新增            " nadd
    print "  移除            " nrem
    print "  属性变化（核心）  " nchg " 处 / " nrowchg " 条"
    print "  派生变化（结构）  " nT2 " 处 / " nrowT2 " 条"
    print "  仅代数变化        " nT3 " 处 / " nrowT3 " 条"
    if (nONLYN + nONLYB > 0) {
        printf "  字段集合变化      +%d 列 / -%d 列", nONLYN, nONLYB
        if (nONLYN > 0) { printf "（新增：" ; for (a = 1; a <= nONLYN; a++) printf "%s%s", (a == 1 ? "" : ", "), ONLYN[a]; printf "）" }
        print ""
    }
    if (nMISS > 0) {
        printf "  ⚠ 新快照缺核心列："
        for (a = 1; a <= nMISS; a++) printf "%s%s", (a == 1 ? "" : ", "), MISS[a]
        print "  —— 条目匹配可能失真，请检查两侧是否为同一工具产出"
    }
    if (nadd + nrem + nchg == 0) print "  → 实质内容没有变化（派生与代数层的变化不算改动）"
    else print "  → 有实质差异，详见报告"
}

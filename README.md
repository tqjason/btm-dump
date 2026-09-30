# btm-dump

**把 `sudo sfltool dumpbtm` 的文本输出，变成结构化数据、可浏览页面和可前后比对的差异报告。**

macOS 后台项（登录项 / 后台代理 / 守护进程 / QuickLook·Spotlight 插件）的**全字段采集 · 导出 · 比对**工具链。
纯 zsh + 系统自带 awk 实现，**零依赖、零安装**。

![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![Shell](https://img.shields.io/badge/shell-zsh%20%2B%20awk-blue)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![License](https://img.shields.io/badge/license-MIT-green)

[English](README.en.md) · [快速开始](#五快速开始) · [字段与术语](#十一字段与术语速查) · [工作原理](#十工作原理)

---

## 一、这是什么

`sfltool dumpbtm` 是 macOS 自带的命令，能把系统的**后台项数据库**导出成文本。凡是「开机或登录后会自动运行、不需要你每次点确认」的东西都在里面：

| 类别 | 例子 |
|---|---|
| 登录项（login item） | 应用注册的启动助手 |
| 后台代理（agent） | 用户或全局作用域下的常驻小进程 |
| 守护进程（daemon） | 以 root 运行的系统级服务 |
| QuickLook / Spotlight 插件 | 预览扩展、索引导入器 |
| 应用与开发者注册项 | 应用自身的注册记录、代码签名主体的归属记录 |

这条命令很实用，但它有**三个硬伤**：

1. **输出是纯文本**——每条记录十几个字段，一台普通 Mac 就有 60～100 条，摊开是近千行，肉眼几乎无法通读；
2. **没有官方文档**——`sfltool` 连 man page 都没有，字段含义只能靠社区逆向；
3. **无法比对**——你想「改一个后台项，看看前后差了什么」，原生手段完全没有。

`btm-dump` 就是补这三块：**一次采集 → 四种格式输出 → 随时前后比对**。

> 本仓库**只包含工具本身**。不含任何真实机器的后台项数据——`examples/` 里是两份完全虚构的合成 dump，供你无 root 试跑。

---

## 二、为什么需要它

市面上有「启动项管理」类图形工具，但它们的问题是**只给结论、不给原始字段**：你看到的是「建议关闭」，看不到 `Disposition` 的原始位、`Parent Identifier` 指向谁、`Generation` 是多少。

而安全排查、合规审计、故障定位这些场景，恰恰需要**原始字段的完整可追溯**。`btm-dump` 的定位是**数据工具**，不是**结论工具**：

- 它**不做风险判定**、不给「该不该关」的建议——那是你的判断；
- 它做的是：**一个字段都不丢地结构化**，并且让「改动前 → 改动后」的差异**精确到「第几条、哪个字段、旧值 → 新值」**。

---

## 三、特点与优势

| 特点 | 具体说明 |
|---|---|
| **零依赖** | 只用 `/bin/zsh` + `/usr/bin/awk` + `/usr/bin/sort` + `/usr/bin/cut`，全部系统自带。不需要 Python、不需要 Homebrew、不需要联网安装 |
| **一个字段都不丢** | 预置字段映射为规范列；**未预置的新字段自动变成 `raw_<原字段名>` 列**。macOS 升级给 dump 加了字段也不会被静默丢掉 |
| **不去重** | 同一标识符被注册多次的记录**原样保留**，只用 `dup_group` 列标记。因为「重复注册」本身就是需要被看见的线索 |
| **不改写原值** | `(null)`、`(0x10010)`、`[ legacy ]` 一律原样保留，要干净表格再加 `-n` |
| **四种格式一次产出** | TSV（无损中间格式）/ CSV（全字段表格）/ JSON（结构化数据）/ HTML（可浏览页面），**同源派生**，不会出现「CSV 少字段而 JSON 有」 |
| **可浏览页面** | 单文件、离线可用。表格视图（列选择 / 筛选 / 排序 / 导出当前视图）+ **8 种关系树** + 字段说明 |
| **中英双语界面** | 界面文案中英各一套，`-L auto/zh/en/both` 选择（默认按系统语言自动判定）；渲染时把另一套裁掉，产出的是**真正单语**的文件。数据文件与比对工具完全不受影响，见 6.4 |
| **可前后比对** | 五层改动分类（新增 / 移除 / 属性变化 / 派生变化 / 仅代数变化）+ **字段集合变化层**，喧闹的噪音不会淹没真实改动 |
| **确定性可复现** | 同一份输入连跑两次，`tsv` 与 `csv` **逐字节一致**。这是「逐行 diff」能成立的前提 |
| **自带自检** | `btm-selftest.js` 用最小 DOM 桩真跑一遍页面逻辑（开发用，正常使用不需要 Node） |

---

## 四、环境要求

| 项 | 要求 |
|---|---|
| 操作系统 | macOS（在 15.x 上开发与验证） |
| 运行时 | `/bin/zsh` + `/usr/bin/awk`（系统自带） |
| 权限 | 实时采集需要 `sudo`；**用 `-f` 读取已有 dump 文本则完全不需要提权** |
| 可选 | Node.js 仅在跑 `btm-selftest.js` 时需要 |

> 采集之所以需要 root，是因为 BTM 数据库位于 `/private/var/db/com.apple.backgroundtaskmanagement/`，普通用户无权读取。

---

## 五、快速开始

不想提权、不想联网，先用内置的**合成示例**跑一遍（30 秒）：

```zsh
git clone https://github.com/tqjason/btm-dump.git
cd btm-dump

# 采集示例数据并解析（不调 sudo）
./btm.sh -f examples/demo-before.txt -l demo-before -o demo-out
./btm.sh -f examples/demo-after.txt  -l demo-after  -o demo-out

# 比对两次快照
./btm-diff.sh demo-out/demo-before-* demo-out/demo-after-*

# 打开浏览页
open demo-out/demo-after-*/btm_items.html
```

想在**自己的机器**上用：

```zsh
# ① 打基线（会调 sudo）
./btm.sh -l before

# ② ……你去改后台项……

# ③ 再打一次快照，然后比对
./btm.sh -l after
./btm-diff.sh snapshots/before-* snapshots/latest
```

---

## 六、用法

### 6.1 `btm.sh` —— 采集 + 解析 + 导出

```
btm.sh [-f <dumpbtm.txt>] [-l <标签>] [-o <输出目录>] [-s <排序口径>] [-L <语言>] [-n] [-q]
btm.sh -r <快照目录> [-L <语言>]   重新渲染该快照的 HTML（模板更新后用，不动数据）
```

| 参数 | 说明 |
|---|---|
| `-f <文件>` | 读取已有的 dumpbtm 文本。**不给则实时执行 `sudo sfltool dumpbtm`** |
| `-l <标签>` | 快照标签，默认 `snapshot`。用于区分「before / after」 |
| `-o <目录>` | 输出根目录，默认 `<脚本目录>/snapshots` |
| `-s <口径>` | 排序口径，见 6.3 |
| `-L <语言>` | 浏览页语言：`auto`（默认）/ `zh` / `en` / `both`，见 6.4 |
| `-n` | 把原值 `(null)` 清空，表格更干净（**默认原样保留**） |
| `-q` | 安静模式，不打印摘要 |
| `-r <目录>` | 只重渲染：读该目录已有的 `btm_items.json` 重新套当前模板生成 HTML |
| `-h` | 显示帮助 |

**关于 `-r` 重渲染模式**：数据文件（`tsv` / `csv` / `json`）和采集信息（`capture.txt` / `meta.json`）**一个字节都不动**，只刷新 HTML。改了浏览页模板后，用它把历史快照的页面更新到最新，既不必重新采集，也不会污染「数据未变」这个事实。

**关于 `sudo`**：脚本沿用 `${SUDO_ASKPASS:+-A}` 写法——配了 `SUDO_ASKPASS` 时自动加 `-A`，避免卡在交互式密码输入（适合从脚本或非交互终端调用）。

### 6.2 `btm-diff.sh` —— 比对两个快照

```zsh
./btm-diff.sh <基线快照目录> <对比快照目录> [--out <输出目录>]
```

两侧都必须是 `btm.sh` 产出的快照目录（含 `btm_items.tsv`）。默认把 `changes.md` / `changes.csv` 写进**对比快照**目录。

### 6.3 排序口径

默认 `scope`：**作用域（系统 `-2` → root `0` → 用户 `501`）→ 持久化机制（daemon → agent → login item → app → 插件 → 开发者父记录）→ 标识符**。标识符是反向域名，所以同一厂商的东西天然聚在一起。

备选：`type`（先按机制）、`vendor`（按签名主体归堆）、`identifier`、`name`、`status`（只看谁在跑）、`file`（还原 dump 原始顺序）。

> **所有口径一律以 `uuid` + `seq` 收尾做 tie-break**——这是「两次导出能逐行 diff」的前提。

### 6.4 浏览页语言

```zsh
./btm.sh -L en                       # 纯英文浏览页
./btm.sh -L both                     # btm_items.html（中英对照）+ btm_items.en.html（纯英文）
./btm.sh -L zh                       # 强制中英对照
./btm.sh -r snapshots/latest -L en   # 只把已有快照的页面换成英文版（数据不动）
```

| 取值 | 效果 |
|---|---|
| `auto`（默认） | 读 macOS 首选语言（`AppleLanguages` → `AppleLocale` → `$LANG`）：以 `zh` 开头出中英对照版，其余出纯英文版 |
| `zh` | 中英对照：表格里「中文列名 + 原始列名」双行，关系树与字段说明用中文 |
| `en` | 纯英文 |
| `both` | 两种各出一份（`btm_items.html` 对照版 + `btm_items.en.html` 英文版） |

三条边界，值得记住：

- **只影响 HTML 的界面文案**。`tsv` / `csv` / `json` 与比对工具的输入输出一个字节都不变——换语言不会让「数据到底变没变」这个问题产生歧义。
- **数据里自带的中文枚举值也不改数据**。列分组、`config_kind`、`exec_scope`、`identifier_scope_zh`、`persistence_zh`、`parent_kind` 的中文取值由 `btm-extract.awk` / `btm-emit.awk` 算出来，英文版靠在模板里挂一张显示映射表换英文；CSV 导出、页面右上角的「导出当前视图 CSV」拿到的仍是原值。
- **模板只维护一份逻辑**。中英两套文案都带着标记放在 `btm-view.tpl.html` 里，渲染时按语言裁掉另一套，所以产出的 HTML 是**真正单语**的（英文版页面里不会夹带中文）。代价是模板里的**实现注释仍是中文**——那是给读源码的人看的，不是页面内容。

> 想给非中文用户一份页面，用 `-L en` 即可；想两份都留着对照，用 `-L both`。

---

## 七、输出什么

一次运行同时产出四种格式，数据源相同，只是视图不同：

| 文件 | 定位 |
|---|---|
| `btm_items.tsv` | **无损中间格式**。制表符分隔，是另外三种格式的源头，也是比对工具的输入。要「逐字核对原始 dump」就看这份 |
| `btm_items.csv` | **全字段表格**。51 列，UTF-8 BOM，Excel / Numbers / 腾讯文档直接打开不乱码。所有字段加引号，避免 Excel 把 UUID 认成日期、把长数字搞成科学计数 |
| `btm_items.json` | **结构化数据**。列表型字段保留为**数组**而非压平；另带 `columns` / `column_meta`（列的中文名与分组）/ `list_columns` / `bool_columns` / `sections` |
| `btm_items.html` | **浏览版**。单文件、离线可用。表格视图 + 8 种关系树 + 字段说明。界面语言由 `-L` 决定，见 6.4 |

另外每次快照还会写：

| 文件 | 内容 |
|---|---|
| `dumpbtm.txt` | 原始文本留档（`-f` 模式是副本，实时模式是采集结果） |
| `capture.txt` | 采集环境与计数，人读（含 `ui_lang`：本次页面用的语言） |
| `meta.json` | 同样的元信息，机器读 |
| `btm_items.en.html` | 只在 `-L both` 时出现：与 `btm_items.html` 同数据，纯英文界面 |

**HTML 里的「选择列」是页面功能，不改数据文件**：CSV / JSON 永远是全字段，列选择只是让你在浏览器里挑着看。选择记在浏览器 `localStorage` 里，所以前后两次快照打开时能保持同一套列，方便对照。

---

## 八、八棵关系树

数据里描述「谁和谁有关系」的字段不止一个，而且**它们的集合并不重合**，所以页面提供了 8 棵独立的树：

| 树 | 依据字段 | 看什么 |
|---|---|---|
| ① 归属树 | `Parent Identifier` | 每个开发者 / 应用下面挂了哪些条目。**主树** |
| ② 嵌入树 | `Embedded Item Identifiers` | 与①方向相反。两个字段对不上的地方会被直接标出来 |
| ③ Bundle 归组树 | `Bundle Identifier` / `Assoc. Bundle IDs` | 同一 App 的条目 + 代理 + 守护进程聚回一堆 |
| ④ 作用域树 | 记录组 UID → 持久化机制 | 还原 dump 原本的三层结构 |
| ⑤ 签名主体树 | `Developer Name` | 一眼看出「哪些东西是同一家签的」 |
| ⑥ 配置来源树 | `config_kind` → `config_dir` | **配置（plist）注册在哪里** |
| ⑦ 可执行落点树 | `exec_scope` → `exec_dir` | **可执行文件落在哪里** |
| ⑧ 代数分组 | `Generation` | **只是分组，不是层级**（见术语表） |

**⑥⑦ 为什么要拆成两棵**：`URL` 与 `Executable Path` 看起来都在说「路径」，但它们回答的是**两个不同的问题**（配置注册在哪 vs 程序落在哪）。混在一棵树里，就会出现「有的节点是配置、有的是可执行文件」的语义混淆。拆开之后两棵树都覆盖全部记录，不适用的集中归入末尾的「无配置路径」/「无独立可执行文件」桶——**一条都不丢**。

统一约定：同一条记录只挂在**第一个匹配到的**父节点下（不会重复出现）；父记录没出现在本次 dump 里时，条目按顶层节点保留、并标注「父记录未登记」，不会被强行搬走，以保证分组归属与 dump 一致；递归带祖先集合和深度上限，遇到循环引用会截断而不是递归到爆。

---

## 九、前后比对

### 9.1 三级匹配

逐级放宽，保证同一项即使换了 UUID 重新注册也能认出来是同一项：

1. `uid + uuid`
2. `uid + match_key`（标识符基名｜持久化机制）
3. `uid + match_key + executable_path`

### 9.2 改动分五层

这是刻意的设计——把它们混在一张表里，真正的人工改动会被噪音淹没：

| 层 | 内容 | 为什么单独一层 |
|---|---|---|
| 一、新增 | 新出现的注册项 | |
| 二、移除 | 消失的注册项 | |
| 三、**属性变化（核心）** | 所有原始字段 + 语义派生列 | **这层才是「你到底改了什么」** |
| 四、派生变化 | `child_count` / `depth` / `node_path` / `dup_group` | 是关系的投影；变了说明有记录换了父级或出现新的重复 |
| 五、仅代数变化 | `generation` | 它会自己变，单列出来避免刷屏（见术语表） |

`seq`、`source_line`、`match_key` 是纯记账，**完全不参与比对**。

### 9.3 零号层：字段集合变化

如果两个快照的**列集合不同**（解析器加了派生列、macOS 升级多出 `raw_*` 列、一边用了 `-n`），只在一边存在的列会单独报成「+N 列 / -N 列」，**不计入逐条改动**。

> 为什么必须有这层：如果按「第一个文件的列位置」去切第二个文件，列集合一旦不同，从差异点往后的所有列都会**整体错位**，产出满屏假改动。本工具按**列名**对齐、取并集，只在双边都存在的列上做逐条比对。顺带还能兜住另一种事故：对比文件缺了 `uid` / `uuid` / `match_key` 这类核心列时会直接告警「条目匹配可能失真」，不会给你一份看起来很正常的错报告。

### 9.4 输出

`changes.md`（人读）+ `changes.csv`（机读），并在终端打印摘要。样例见 [`examples/demo-changes.md`](examples/demo-changes.md)——那是用 `examples/` 里两份合成 dump 跑出来的**真实输出**。

---

## 十、工作原理

### 10.1 流水线

```
                        sudo sfltool dumpbtm
                                 │
                                 ▼
                         dumpbtm.txt          ← 原始文本，留档
                                 │
                 btm-extract.awk │ ① 解析：文本 → 无损 TSV
                                 │    · 已知字段 → 规范列
                                 │    · 未知字段 → 自动成为 raw_* 列
                                 │    · 不去重，重复项只标记 dup_group
                                 │    · 计算派生列（分类 / 层级 / 归组键）
                                 ▼
                        btm_items.tsv         ← 无损中间格式（比对工具的输入）
                                 │
                 btm-emit.awk    │ ② 导出
                        ┌────────┴────────┐
                        ▼                 ▼
                btm_items.csv     btm_items.json
                 全字段表格         结构化数据
                                          │
        btm-view.tpl.html                │ ③ 注入模板
        （页面骨架 + 交互 JS）  ───────────┤
                                          ▼
                                  btm_items.html
                            表格 + 列选择 + 8 棵关系树
```

### 10.2 三个关键设计决策

**① 为什么要有「无损 TSV」这一层中间格式**

如果直接从文本分别生成 CSV 和 JSON，两边的字段处理逻辑会各写一遍，早晚漂移（典型症状：CSV 少了字段但 JSON 有）。中间放一层 TSV，所有出口都从它派生，**一致性变成结构性保证而不是靠自觉**。它还顺便成为比对工具的输入。

**② 为什么派生列在 awk 里算、而不是在页面里算**

`config_kind` / `exec_scope` 这类分类，如果只在 HTML 的 JS 里算，那么「表格里看到的」和「树里看到的」就是两套代码算出来的，容易打架。现在它们在解析阶段就算好、落进列里，**页面只是读列**——表格与树的口径因此不可能漂移。

**③ 为什么 `dumpbtm` 的字段名要「已知 + 未知」两套处理**

BTM 是未公开接口，Apple 随时可能加字段。所以解析器维护一份**已知字段表**（映射为规范列名），其余一律原样变成 `raw_<原字段名>` 列。结果是：**加字段不会丢数据，只会多一列**。

### 10.3 确定性怎么保证

| 手段 | 作用 |
|---|---|
| 所有排序口径都以 `uuid` + `seq` 收尾 | 消除并列项的顺序不确定性 |
| `LC_ALL=C sort` | 不受本地化排序规则影响 |
| 重跑不产生随机内容 | 同一份输入两次运行 → `tsv` / `csv` 逐字节一致 |
| 时间戳只写进 `meta.json` / `capture.txt` | 不进数据文件，所以数据文件可被 diff |

---

## 十一、字段与术语速查

### 11.1 背景名词

| 名词 | 解释 |
|---|---|
| **BTM** | Background Task Management。macOS 统一管理后台持久化项的系统组件 |
| **`sfltool`** | macOS 自带的命令行工具。`sudo sfltool dumpbtm` 导出 BTM 数据库。**未公开、无 man page**，字段含义靠社区逆向 |
| **BTM 数据库** | `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm`。需 root 才能读取 |
| **`dumpbtm` 输出结构** | 按 **UID 记录组**分节 → `Items:` → 每条以 ` #N:` 开头 → 字段形如 `Key: value`（字段名右对齐到第 21 列）→ 末尾可跟 `Embedded Item Identifiers:` 子列表 |

### 11.2 记录组（UID）

| UID | 含义 |
|---|---|
| `-2` | **合成组**。dump 把散落在各处的后台项汇到这里，绝大多数「系统级」条目在这 |
| `0` | root |
| `501` | 普通用户（第一个管理员账号） |

> 同一个软件常常同时出现在 `-2` 和 `501` 里，**这不是重复**，而是它在两个作用域各注册了一份。

### 11.3 Generation（代数）

> **它不代表父子代际，也不是「第几代」。它是 BTM 给每条记录维护的一个整数计数器。**

Apple 没有公开它的定义，所以分两部分说：

**能确定的：**
- 它是每条记录上的一个独立整数，与 `Parent Identifier` 描述的层级**完全无关**。
- 同一个软件的不同条目数值差异很大，说明它是**按条目**维护的。

**经验判断（无官方佐证，按「合理但未证实」看待）：**
- 「同一条记录每被重新注册一次，这个数就往上走」。
- 支持这个判断的结构性观察：`developer` 开发者父记录（只在安装时写一次）普遍停在很小的值；而**反复重新注册登录项的应用条目明显更高**。

**它真正的实用价值是反向的：**

> 因为 Generation 会自己变，所以两次快照之间**「只有 Generation 变了」通常不意味着你做了什么改动**。

比较工具因此把它单列成第五层，不跟核心字段混在一起——否则它会把真正的改动刷没。

> ⚠️ **不要用它做因果推断或安全判定。** 上面「重新注册即自增」只是经验解读。要确定语义，只能用一台可以反复重启的实验机，对同一条记录观察多次 dump 的差值来验证。
>
> 页面里的「字段说明」页会**从你当前这份数据的实际数值**推导这段话，而不是写死某个数字。

### 11.4 配置路径 ≠ 可执行文件路径

这是最容易混的一对字段：

| 字段 | 回答的问题 | 指向的东西 |
|---|---|---|
| `URL` → `url_path` | **配置（plist / 应用包）注册在哪里** | plist 文件，或应用包 / 应用包内的组件本身 |
| `Executable Path` | **真正被执行的程序落在哪里** | 二进制的实际落点 |

任意一条记录都属于下面三种形态之一：

| 形态 | 说明 |
|---|---|
| 两者都有 | 配置注册在某处，另有独立可执行文件（daemon / agent 都是这种） |
| 只有 `URL` | 配置即载体：登录项 helper、QuickLook 扩展、Spotlight 导入器、把自己注册为登录项的应用 |
| 两者都无 | developer 父记录，只表示「归属」，没有落点 |

配套派生列（都是**分类**，不是判断）：

| 列 | 依据 | 取值 |
|---|---|---|
| `config_kind` | `url_path` | 系统守护进程配置 / 全局代理配置 / 用户代理配置 / 系统内置配置 / 应用包自身 / 应用包内嵌组件 / 其它绝对路径 / 其它相对路径 / 无配置路径 |
| `config_dir` | `url_path` | 配置所属目录。**若该路径本身就是 `.app` 包，则上溯到它所在目录**——否则 `/Applications` 下每个应用都会变成一个只含 1 条的假分组 |
| `exec_scope` | `executable_path` | 系统特权 Helper / 系统应用支持目录 / 系统库其它位置 / 系统内置 / 应用包内（Contents/MacOS）/ 应用包内（其它）/ 本地安装目录（`/usr/local`）/ 用户主目录（**用户可写**）/ 相对路径 / 其它绝对路径 / 无独立可执行文件 |
| `exec_dir` | `executable_path` | 可执行文件所属目录（不做上溯，保持原样） |

判定规则细节：

- 判定顺序即优先级，先匹配者胜。
- 「路径中间出现 `/Contents/`」优先判为**应用包内嵌组件**，而不是应用包自身——登录项 helper、QuickLook 扩展、Spotlight 导入器都是这个形态（相对路径，相对的是所属应用包）。
- 开头的 `./` 会先归一化掉再判定，但**列里保留原值**。
- 「无配置路径」与「无独立可执行文件」这两个桶是为了**一条都不丢**而存在的，不是错误。

### 11.5 标识符前缀数字

标识符形如 `16.com.example.daemon`，点号前的数字是作用域码，与 `Type` 的取值域一致：

| 前缀 | 含义 | 十六进制 |
|---:|---|---|
| `2` | 应用 app | `0x2` |
| `4` | 登录项 login item | `0x4` |
| `8` | 后台代理 agent | `0x8` |
| `16` | 守护进程 daemon | `0x10` |
| `64` | Spotlight 插件 | `0x40` |
| `2048` | QuickLook 插件 | `0x800` |
| （无前缀） | developer 父记录，`Identifier` 就是开发者名 | `0x20` |

已拆成 `identifier_scope` / `identifier_scope_zh` / `identifier_base` 三列，方便按「去掉前缀的名字」聚合。

### 11.6 处置状态（Disposition）与标志（Flags）

形如 `[enabled, allowed, visible, notified] (0xb)`，拆成 5 个布尔列：`enabled`、`allowed`、`visible`、`notified`、`hidden`（`visible` 取反）。

值得留意 `enabled` 与 `allowed` 的四种组合是否自相矛盾——`enabled + disallowed` 或 `disabled + allowed` 属于已知的数据库不一致状态，用筛选里的「仅已禁止」可以快速看一遍。

### 11.7 完整 51 列

<details>
<summary>展开全部列（点击）</summary>

**记录组（5）** — `uid` 记录组 UID · `uid_domain` 作用域 · `group_uuid` 记录组 UUID · `sm_migrated` 已迁移 ServiceManagement · `ls_registered` 已注册 LaunchServices

**身份（5）** — `seq` 组内序号 · `uuid` 条目 UUID · `name` 名称 · `developer_name` 开发者名称 · `team_identifier` 签名 Team ID

**类型（4）** — `type_raw` 类型（原文） · `type_mechanism` 持久化机制 · `type_modifiers` 类型修饰词 · `type_hex` 类型码

**状态（10）** — `flags_raw` 标志（原文） · `flags_list` 标志列表 · `flags_hex` 标志码 · `disposition_raw` 处置状态（原文） · `disposition_hex` 处置码 · `enabled` 已启用 · `allowed` 已允许 · `visible` 可见 · `notified` 已通知 · `hidden` 隐藏

**标识（4）** — `identifier` 标识符 · `identifier_scope` 作用域码 · `identifier_scope_zh` 作用域说明 · `identifier_base` 标识符基名

**配置与落点（7）** — `url` 注册落点 URL · `url_path` 配置路径 · `config_kind` 配置注册位置类别 · `config_dir` 配置所属目录 · `executable_path` 可执行文件路径 · `exec_scope` 可执行落点类别 · `exec_dir` 可执行文件所属目录

**关系（8）** — `bundle_identifier` Bundle ID · `bundle_key` Bundle 归组键 · `parent_identifier` 父标识符 · `parent_kind` 父类型 · `assoc_bundle_ids` 关联 Bundle IDs · `assoc_count` 关联数量 · `embedded_item_identifiers` 嵌入项标识符 · `embedded_count` 嵌入数量

**变更（4）** — `generation` 代数 · `dup_group` 重复注册组 · `match_key` 比对主键 · `source_line` 源文件行号

**结构（4）** — `child_count` 子项数 · `depth` 归属层级 · `node_path` 归属链 · `persistence_zh` 机制说明

**外加** `raw_*` —— 未预置的新字段自动成列，数量不固定。

</details>

### 11.8 其余关键列

| 列 | 说明 |
|---|---|
| `parent_identifier` | 「我这条记录是被谁注册的」。指向的可能是 developer 父记录（如 `Example Corp`），也可能是某个应用条目（如 `2.com.example.toolbox`） |
| `embedded_item_identifiers` | 「我这条记录内嵌了哪些子项」。与 `parent_identifier` 是**同一关系的两个方向，集合并不完全重合**——两者对不上时，工具会照原样标注而不是替你「修正」 |
| `bundle_key` | 归组用的键：优先自身 `Bundle Identifier`，其次第一个 `Assoc. Bundle IDs`。用标识符基名兜底会让开发者记录和各代理被拆成一堆只含 1 条的假分组，所以不做这个兜底 |
| `dup_group` | 同一 UID 下「标识符基名 + 持久化机制」完全相同的多条记录打同一编号。**一条都没删，只是标记** |
| `match_key` | 跨快照比对用的语义主键（标识符基名｜机制） |
| `source_line` | 该条在原始 dump 里的行号，方便逐字回溯 |
| `node_path` | 完整归属链，如 `开发者 › 应用 › 条目` |

---

## 十二、为什么是 shell 而不是 Python

早期版本用 Python（只用标准库）实现。它有一个真实脆弱点：**macOS 上的 `/usr/bin/python3` 本质是 Xcode Command Line Tools 的附属品**——机器没装 CLT 时，执行它会弹出安装提示而不是运行。而这个工具的价值恰恰在于「随时能跑一次」，所以去掉这层依赖值得。

改成 shell 能做到同等功能，靠三点（与 §10.2 呼应）：

1. **解析用 awk**——这本来就是 awk 的主场，只是不能像常见的一行流脚本那样在导出阶段就把字段砍掉；
2. **HTML 的交互全在浏览器端**——列选择、排序、筛选、关系树都是页面里的 JS，shell 只负责把 JSON 塞进去；
3. **CSV / JSON 都从同一份无损 TSV 派生**——一份中间格式，多个出口。

**取舍**：macOS 自带的是 BWK awk（不是 gawk），所以脚本只用了 **POSIX 子集**（没用 `gensub`、`match` 捕获组、多维数组），排序交给 `/usr/bin/sort` 而不是在 awk 里手写。另外字符串比较用 `LC_ALL=C` 以保证确定性。

---

## 十三、目录结构

```
btm-dump/
├── btm.sh                主脚本：采集 + 解析 + 一次生成全部输出
├── btm-extract.awk       ① 解析：dumpbtm 文本 → 无损 TSV（含派生列、排序）
├── btm-emit.awk          ② 导出：TSV → CSV / JSON / 列名映射表
├── btm-view.tpl.html     ③ 浏览页模板（表格 + 列选择 + 8 棵关系树 + 字段说明）
├── btm-diff.sh           比对入口
├── btm-diff.awk          比对逻辑本体
├── btm-selftest.js       页面自检（仅开发用，需要 Node）
├── examples/
│   ├── demo-before.txt   合成示例：改动前（全部虚构，无任何真实机器数据）
│   ├── demo-after.txt    合成示例：改动后
│   └── demo-changes.md   上面两份跑出来的真实比对报告
├── README.md             中文说明（本文件）
├── README.en.md          English README
├── LICENSE               MIT
└── .gitignore            忽略 snapshots/ 等本地采集产物
```

运行 `btm.sh` 后会生成 `snapshots/<标签>-<时间戳>/`（已加入 `.gitignore`）。

---

## 十四、开发与自检

页面交互逻辑（表格 / 排序 / 筛选 / 列面板 / 8 棵树 / 折叠 / 详情 / 字段说明）用 Node + 最小 DOM 桩做了自动化测试，**同一套断言对中文对照版和纯英文版都跑**（期望文案从页面自己的字典推导，不写死任何一种语言）：

```zsh
./btm.sh -f examples/demo-before.txt -l t -o /tmp/t -L both
node btm-selftest.js /tmp/t/latest/btm_items.html        # 中文对照版
node btm-selftest.js /tmp/t/latest/btm_items.en.html     # 纯英文版
node btm-selftest.js --i18n btm-view.tpl.html            # 只查模板双语字典，不需要快照
```

断言是**从数据推导**的（不绑定任何一台机器的软件清单），因此换一台机器、换一份快照同样成立。重点覆盖：

- 每棵树的条目节点数必须 **≤ 总条数**（防止重复挂载）
- 配置树只出现配置类别、可执行树只出现可执行类别（**互不串台**，这是「两棵树确实建立在两个不同字段上」的硬证据）
- 两个「无」桶的条数必须与数据里 `URL` / `Executable Path` 为空的条数吻合
- **折叠后必须还能展开**——这是一条回归测试。历史 bug：原实现用「DOM 里有没有 `.tkids` 元素」判断节点有没有子节点，而折叠状态下该元素根本不渲染，于是退化成「只能折叠、无法展开」。修法是把「有子节点」写进 `data-kids` 属性。测试用修复前的逻辑反向验证过，确认它不是摆设
- **类别归属必须精确匹配分组标签元素**，不能用裸子串——英文标签 `Application Support` 正好是目录路径 `/Library/Application Support/…` 的子串，裸子串判定会把配置树里的一条普通路径误报成「两棵树串台」。这条也是实测踩出来的
- **中英两份字典的键位必须一一对应**，且 en 侧不允许出现中文或全角字符（`--i18n` 模式）。漏翻的键会在页面上直接显示成键名，所以这道检查挡的是「加了界面文案忘了另一种语言」

---

## 十五、已知边界

本工具**只处理元数据**，请务必了解它的能力边界：

- **看不到二进制内容**。它只能说清「谁注册了、签名是谁、程序放在哪、是否启用」，看不到可执行文件里有什么代码。要坐实可疑行为还需要哈希比对、签名校验与流量分析。
- **不做风险判定**。工具不输出「安全 / 危险」的结论，只输出事实与差异。
- **`Generation` 的语义未证实**，见 §11.3。
- **`dumpbtm` 是未公开接口**，Apple 随时可能改输出格式。真改了的话，未预置字段会被 `raw_*` 自动接住（不会丢），但少数派生列可能需要跟着调整——到那时改 `btm-extract.awk` 里对应的那一段即可。
- **`url_path` 只解了 `%20` / `%2F` / `%40`** 三种百分号转义，其余原样保留。
- **比对工具的键匹配是「最后一条胜出」**：若同一 UID 下存在 `(uid, match_key, executable_path)` 完全相同的双胞胎记录，它们会先被第①级 uuid 匹配分走，正常情况不受影响；只有在两条记录连 UUID 都变了的情况下才可能错配。
- **报告里的中文列名表只在 `btm-emit.awk` 维护一处**（`btm-diff.sh` 通过 `MODE=colmap` 复用它），加字段时记得同步。
- **英文版只翻界面，不翻数据**。`-L` 与 `tsv` / `csv` / `json` 无关；模板里的实现注释仍是中文（模板只维护一份逻辑，不复制成两份）。数据侧的列中文名表在 `btm-emit.awk`，界面侧的英文列名表在模板字典里（`col.<列名>`），两层各管一段、互不干扰——所以新增列时两处都要补一句。

---

## 十六、License

[MIT](LICENSE)

`sfltool` / BTM 是 Apple 的未公开接口，本项目仅解析其**文本输出**，不调用私有 API、不修改系统。

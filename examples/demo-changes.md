# 后台项快照比较报告

- **基线**：`demo-out/demo-before-<时间戳>`　2026-09-30T11:38:45+0800　16 条
- **对比**：`demo-out/demo-after-<时间戳>`　2026-09-30T11:38:46+0800　16 条
- **匹配方式**：① uid+uuid → ② uid+标识符基名+机制 → ③ 再加可执行路径
- **不参与比对**：`seq`、`source_line`、`match_key`（纯记账）；`generation` 单列一层

## 摘要

| 类别 | 处数 | 涉及条目 |
|---|---:|---:|
| 新增 | 1 | 1 |
| 移除 | 1 | 1 |
| 属性变化（核心字段） | 9 | 3 |
| 派生变化（结构 / 标记） | 0 | 0 |
| 仅代数变化（Generation） | 1 | 1 |

## 一、新增（1 条）

| UID | 名称 | 标识符 | 机制 | 启用 | 落点 |
|---|---|---|---|---|---|
| -2 | `net.example.netd` | `16.net.example.netd` | daemon | TRUE | `/Library/PrivilegedHelperTools/net.example.netd` |

## 二、移除（1 条）

| UID | 名称 | 标识符 | 机制 | 启用 | 落点 |
|---|---|---|---|---|---|
| -2 | `com.example.qlplugin` | `2048.com.example.qlplugin` | quicklook | TRUE | *(空)* |

## 三、属性变化 —— 核心字段（9 处，涉及 3 条）

| UID | 名称 | 标识符 | 字段 | 中文名 | 旧值 | 新值 |
|---|---|---|---|---|---|---|
| -2 | `net.example.helperd` | `16.net.example.helperd` | `disposition_raw` | 处置状态（原文） | `[enabled, allowed, visible, notified] (0xb)` | `[disabled, disallowed, visible, notified] (0xa)` |
| -2 | `net.example.helperd` | `16.net.example.helperd` | `disposition_hex` | 处置码 | `0xb` | `0xa` |
| -2 | `net.example.helperd` | `16.net.example.helperd` | `enabled` | 已启用 | `TRUE` | `FALSE` |
| -2 | `net.example.helperd` | `16.net.example.helperd` | `allowed` | 已允许 | `TRUE` | `FALSE` |
| -2 | `Example Corp` | `Example Corp` | `embedded_item_identifiers` | 嵌入项标识符 | `16.net.example.helperd` | `16.net.example.helperd \| 16.net.example.netd` |
| -2 | `Example Corp` | `Example Corp` | `embedded_count` | 嵌入数量 | `1` | `2` |
| 0 | `net.example.rootd` | `16.net.example.rootd` | `executable_path` | 可执行文件路径 | `/Library/PrivilegedHelperTools/net.example.rootd` | `/Library/Application Support/Example/Helpers/net.example.rootd` |
| 0 | `net.example.rootd` | `16.net.example.rootd` | `exec_scope` | 可执行落点类别 | `系统特权 Helper` | `系统应用支持目录` |
| 0 | `net.example.rootd` | `16.net.example.rootd` | `exec_dir` | 可执行文件所属目录 | `/Library/PrivilegedHelperTools` | `/Library/Application Support/Example/Helpers` |

## 四、派生变化 —— 结构 / 标记（0 处，涉及 0 条）

无。

## 五、仅代数变化 —— Generation（1 处，涉及 1 条）

`Generation` 是 BTM 自己的计数器，会随记录被重新注册而自增，**不代表你做了什么改动**。
单列这一层，就是为了不让它把上面第三层的真实改动冲淡。列在这里的条目，若同时出现在第三层，那才需要看。

| UID | 名称 | 标识符 | 旧值 | 新值 |
|---|---|---|---|---|
| -2 | `net.example.meterd` | `16.net.example.meterd` | 2 | 3 |

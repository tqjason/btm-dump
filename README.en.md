# btm-dump

**Turn the text output of `sudo sfltool dumpbtm` into structured data, a browsable page, and a before/after diff report.**

A **full-field capture · export · diff** toolkit for macOS background items (login items, background agents, daemons, QuickLook / Spotlight plug-ins).
Pure zsh + the system's own awk. **Zero dependencies, zero installation.**

![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![Shell](https://img.shields.io/badge/shell-zsh%20%2B%20awk-blue)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![License](https://img.shields.io/badge/license-MIT-green)

[中文说明](README.md) · [Quick start](#5-quick-start) · [Fields & glossary](#11-fields--glossary) · [How it works](#10-how-it-works)

> Note: the tool's UI, column names and generated reports are in Chinese. This document describes the same tool in English.

---

## 1. What is this

`sfltool dumpbtm` is a built-in macOS command that exports the system's **background item database** as text. Anything that "runs automatically at boot or login without asking you every time" is in there:

| Category | Examples |
|---|---|
| Login items | helper apps registered by applications |
| Background agents | small persistent processes scoped to a user or all users |
| Daemons | system services running as root |
| QuickLook / Spotlight plug-ins | preview extensions, index importers |
| App & developer registrations | an app's own registration record, and the code-signing owner's record |

The command is genuinely useful, but it has **three hard problems**:

1. **The output is plain text** — a dozen-plus fields per record, 60–100 records on an ordinary Mac. That's nearly a thousand lines, unreadable by eye.
2. **It is undocumented** — `sfltool` doesn't even have a man page; field meanings come from community reverse-engineering.
3. **There is no way to diff it** — "change one background item and see exactly what changed" is impossible with the built-in tooling.

`btm-dump` fills those three gaps: **one capture → four output formats → diff anytime**.

> This repository contains **the tool only**. There is no real-machine data here — `examples/` holds two entirely fictional synthetic dumps so you can try it without root.

---

## 2. Why it exists

There are GUI "startup item manager" apps, but their weakness is that they **give you conclusions, not raw fields**: you see "recommended to disable", not the raw `Disposition` bits, who the `Parent Identifier` points at, or what `Generation` is.

Security triage, compliance auditing and troubleshooting all need **complete, traceable raw fields**. `btm-dump` is a **data tool**, not a **verdict tool**:

- It makes **no risk judgements** and gives no "should you disable this" advice — that's your call.
- What it does: **structure the data with zero field loss**, and make a "before → after" diff **precise down to which record, which field, old value → new value**.

---

## 3. Features and advantages

| Feature | Detail |
|---|---|
| **Zero dependencies** | Uses only `/bin/zsh` + `/usr/bin/awk` + `/usr/bin/sort` + `/usr/bin/cut`, all built into macOS. No Python, no Homebrew, no network install |
| **No field is lost** | Known fields map to canonical columns; **unrecognised fields automatically become `raw_<original name>` columns**. If a macOS update adds a field to the dump, it is captured, not silently dropped |
| **No de-duplication** | Records sharing an identifier are **kept as-is**, merely flagged in the `dup_group` column — because "registered twice" is itself a signal worth seeing |
| **No value rewriting** | `(null)`, `(0x10010)`, `[ legacy ]` are preserved verbatim. Add `-n` if you want a cleaner table |
| **Four formats per run** | TSV (lossless intermediate) / CSV (full-field table) / JSON (structured data) / HTML (browsable page) — all derived from one source, so "CSV is missing a field JSON has" cannot happen |
| **Browsable page** | Single file, works offline. Table view (column picker / filter / sort / export current view) + **8 relationship trees** + an in-page field reference |
| **Bilingual interface** | A 中文 / English toggle in the top-right corner; defaults to your browser language and remembers a manual choice locally. One HTML only — data files and the diff tool are completely unaffected, see 6.4 |
| **Before/after diff** | Five change tiers (added / removed / attribute / derived / generation-only) plus a **column-set change layer**, so noise never drowns the real edits |
| **Deterministic** | The same input run twice produces **byte-identical** `tsv` and `csv`. This is what makes line-by-line diffing meaningful |
| **Ships with a self-test** | `btm-selftest.js` runs the page logic for real against a minimal DOM stub (development only; normal use needs no Node) |

---

## 4. Requirements

| Item | Requirement |
|---|---|
| OS | macOS (developed and verified on 15.x) |
| Runtime | `/bin/zsh` + `/usr/bin/awk` (both built in) |
| Privileges | Live capture needs `sudo`; **reading an existing dump with `-f` needs no privileges at all** |
| Optional | Node.js only for running `btm-selftest.js` |

> Capture needs root because the BTM database lives at `/private/var/db/com.apple.backgroundtaskmanagement/`, unreadable by normal users.

---

## 5. Quick start

Try it on the bundled **synthetic example** first — no root, no network (30 seconds):

```zsh
git clone https://github.com/tqjason/btm-dump.git
cd btm-dump

# Capture and parse the example data (no sudo involved)
./btm.sh -f examples/demo-before.txt -l demo-before -o demo-out
./btm.sh -f examples/demo-after.txt  -l demo-after  -o demo-out

# Diff the two snapshots
./btm-diff.sh demo-out/demo-before-* demo-out/demo-after-*

# Open the browsable page
open demo-out/demo-after-*/btm_items.html
```

To use it on **your own machine**:

```zsh
# 1) Take a baseline (this calls sudo)
./btm.sh -l before

# 2) ... change some background items ...

# 3) Capture again, then diff
./btm.sh -l after
./btm-diff.sh snapshots/before-* snapshots/latest
```

---

## 6. Usage

### 6.1 `btm.sh` — capture + parse + export

```
btm.sh [-f <dumpbtm.txt>] [-l <label>] [-o <outdir>] [-s <sort>] [-n] [-q]
btm.sh -r <snapshot-dir>    Re-render that snapshot's HTML (no data touched)
```

| Option | Meaning |
|---|---|
| `-f <file>` | Read an existing dumpbtm file. **Without it, runs `sudo sfltool dumpbtm` live** |
| `-l <label>` | Snapshot label, default `snapshot`. Use it to distinguish "before / after" |
| `-o <dir>` | Output root, default `<script dir>/snapshots` |
| `-s <sort>` | Sort preset, see 6.3 |
| `-n` | Blank out `(null)` values for a cleaner table (**default: preserved verbatim**) |
| `-q` | Quiet mode, no summary printed |
| `-r <dir>` | Re-render only: re-apply the current page template to that directory's existing `btm_items.json` |
| `-h` | Show help |

**About `-r` (re-render)**: the data files (`tsv` / `csv` / `json`) and capture info (`capture.txt` / `meta.json`) are left **byte-for-byte untouched**; only the HTML is refreshed. After editing the page template, use it to bring old snapshots up to date without re-capturing, and without falsifying the fact that the data didn't change.

**About `sudo`**: the script uses `${SUDO_ASKPASS:+-A}` — if `SUDO_ASKPASS` is configured it adds `-A` automatically, avoiding an interactive password prompt (handy when called from scripts or non-interactive terminals).

### 6.2 `btm-diff.sh` — diff two snapshots

```zsh
./btm-diff.sh <baseline-snapshot-dir> <comparison-snapshot-dir> [--out <dir>]
```

Both sides must be snapshot directories produced by `btm.sh` (containing `btm_items.tsv`). By default `changes.md` / `changes.csv` are written into the **comparison** snapshot directory.

### 6.3 Sort presets

Default `scope`: **scope (system `-2` → root `0` → user `501`) → persistence mechanism (daemon → agent → login item → app → plug-in → developer parent) → identifier**. Identifiers are reverse-DNS, so one vendor's items naturally cluster.

Alternatives: `type` (mechanism first), `vendor` (group by signing subject), `identifier`, `name`, `status` (only what's running), `file` (original dump order).

> **Every preset ends with `uuid` + `seq` as a tie-breaker** — that is the precondition for "two exports can be diffed line by line".

### 6.4 Page language

The page is rendered **once**, and the language is switched *inside the page*: there is a 中文 / English toggle in the top-right corner.

- **Defaults to your browser**: if `navigator.languages[0]` starts with `zh` (`zh-CN` / `zh-Hans` / `zh-TW` / `zh_CN`…) you get the bilingual view, otherwise English.
- **A manual switch is remembered**: the choice is stored in `localStorage` (key `btm.lang`) and reused the next time you open the page in that browser.
- **Switching does not reload the page and does not lose state**: the current view, filters, table sort, column selection and expanded tree nodes all survive.

```zsh
./btm.sh                        # one btm_items.html; the reader picks the language
./btm.sh -r snapshots/latest    # re-render after a template change; language comes along
```

| Variant | What it looks like |
|---|---|
| 中文 | Bilingual: Chinese column name on the first line with the raw column key under it; trees and field reference in Chinese |
| English | English throughout — interface text *and* the Chinese enum values carried by the data |

Three boundaries worth remembering:

- **It only affects the HTML's interface text.** `tsv` / `csv` / `json` and everything the diff tool reads and writes stay byte-for-byte identical — switching language can never muddy the question "did the data actually change?". And since only one HTML is produced, there is no "which file is in which language" ambiguity either.
- **Chinese enum values carried by the data are not rewritten either.** Column groups and the values of `config_kind`, `exec_scope`, `identifier_scope_zh`, `persistence_zh` and `parent_kind` are produced by `btm-extract.awk` / `btm-emit.awk`; the English view translates them through a display map held in the template. The CSV export and the page's own "Export view as CSV" still hand you the original values.
- **The template keeps a single copy of the logic, with both sets of text.** Both dictionaries live in `btm-view.tpl.html` and the page reads whichever one the current language points at. The trade-off is that **implementation comments in the template remain Chinese**; they are for whoever reads the source, not page content.

> The 中文 / English buttons spell each language **in its own language** on purpose — they are not translated. Otherwise an English interface would have no way back to Chinese (GitHub and Wikipedia do the same). They are also the only place in the page where both languages appear together.

---

## 7. What you get

One run produces four formats from the same data — different views, not different data:

| File | Purpose |
|---|---|
| `btm_items.tsv` | **Lossless intermediate.** Tab-separated; the source of the other three formats and the input to the diff tool. This is the file to check "character-for-character against the original dump" |
| `btm_items.csv` | **Full-field table.** 51 columns, UTF-8 BOM, opens cleanly in Excel / Numbers / Google Sheets. Every field is quoted so Excel won't turn UUIDs into dates or long numbers into scientific notation |
| `btm_items.json` | **Structured data.** List-valued fields stay **arrays** rather than being flattened; also carries `columns` / `column_meta` / `list_columns` / `bool_columns` / `sections` |
| `btm_items.html` | **Browsable page.** Single file, works offline. Table view + 8 relationship trees + field reference. The interface language is switched inside the page, see 6.4 |

Plus, per snapshot:

| File | Content |
|---|---|
| `dumpbtm.txt` | The raw text, archived (a copy with `-f`, the capture itself when live) |
| `capture.txt` | Capture environment and counts, human-readable |
| `meta.json` | The same metadata, machine-readable |

**The column picker in the HTML is a page feature and does not change data files**: CSV / JSON always carry every field. Your selection is stored in the browser's `localStorage`, so opening a "before" and an "after" snapshot keeps the same column set for easy comparison.

---

## 8. The eight relationship trees

More than one field describes "who relates to whom", and **their sets do not coincide** — hence 8 independent trees:

| Tree | Based on | Shows |
|---|---|---|
| ① Ownership | `Parent Identifier` | What hangs under each developer / app. **The primary tree** |
| ② Embedding | `Embedded Item Identifiers` | The reverse direction of ①. Disagreements between the two fields are flagged |
| ③ Bundle grouping | `Bundle Identifier` / `Assoc. Bundle IDs` | An app's entries, agents and daemons pulled back together |
| ④ Scope | record group UID → mechanism | Reconstructs the dump's original three-level structure |
| ⑤ Signing subject | `Developer Name` | At a glance: what was signed by the same party |
| ⑥ Configuration origin | `config_kind` → `config_dir` | **Where the configuration (plist) is registered** |
| ⑦ Executable landing | `exec_scope` → `exec_dir` | **Where the executable actually lives** |
| ⑧ Generation buckets | `Generation` | **Grouping only, not a hierarchy** (see glossary) |

**Why ⑥ and ⑦ are separate**: `URL` and `Executable Path` both look like "a path", but they answer **two different questions** (where the config is registered vs where the program lives). Mixing them into one tree produces nodes where some are configurations and some are executables — a confusing model. Split apart, both trees still cover every record, and inapplicable ones collect into trailing "no configuration path" / "no standalone executable" buckets — **nothing is dropped**.

Common conventions: each record hangs under the **first matching** parent only (so it never appears twice); when the parent record does not appear anywhere in this dump, the item stays at the top level and is annotated "parent not registered" rather than being forcibly relocated, keeping grouping faithful to the dump; recursion carries an ancestor set and a depth cap, so a circular reference truncates instead of blowing the stack.

---

## 9. Diffing

### 9.1 Three-level matching

Progressively relaxed, so an item re-registered with a new UUID is still recognised as the same item:

1. `uid + uuid`
2. `uid + match_key` (identifier base name | mechanism)
3. `uid + match_key + executable_path`

### 9.2 Five change tiers

A deliberate design — mixed into one table, real edits get buried in noise:

| Tier | Content | Why it's separate |
|---|---|---|
| 1. Added | newly registered items | |
| 2. Removed | items that disappeared | |
| 3. **Attribute changes (core)** | all raw fields + semantic derived columns | **This is "what you actually changed"** |
| 4. Derived changes | `child_count` / `depth` / `node_path` / `dup_group` | Projections of relationships; a change means something re-parented or a new duplicate appeared |
| 5. Generation-only | `generation` | It changes on its own; separated so it doesn't flood the output (see glossary) |

`seq`, `source_line` and `match_key` are bookkeeping and **never participate in comparison**.

### 9.3 Tier zero: column-set changes

If the two snapshots have **different column sets** (a new derived column, a new `raw_*` column from a macOS update, `-n` used on one side), columns present on only one side are reported separately as "+N columns / -N columns" and are **not counted as per-record changes**.

> Why this tier must exist: if you slice the second file by the *first* file's column positions, then as soon as the column sets differ, every column after the divergence point is **shifted**, producing a screenful of phantom changes. This tool aligns by **column name**, takes the union, and compares per-record only on columns present on both sides. It also catches another failure mode: if the comparison file is missing core columns like `uid` / `uuid` / `match_key`, it warns that "item matching may be unreliable" rather than handing you a plausible-looking wrong report.

### 9.4 Output

`changes.md` (human-readable) + `changes.csv` (machine-readable), plus a summary printed to the terminal. For a sample see [`examples/demo-changes.md`](examples/demo-changes.md) — that is the **actual output** produced from the two synthetic dumps in `examples/`.

---

## 10. How it works

### 10.1 Pipeline

```
                        sudo sfltool dumpbtm
                                 │
                                 ▼
                         dumpbtm.txt          <- raw text, archived
                                 │
                 btm-extract.awk │ (1) parse: text -> lossless TSV
                                 │     - known fields -> canonical columns
                                 │     - unknown fields -> raw_* columns
                                 │     - no de-duplication; duplicates flagged
                                 │     - derived columns computed here
                                 ▼
                        btm_items.tsv         <- lossless intermediate (diff input)
                                 │
                 btm-emit.awk    │ (2) export
                        ┌────────┴────────┐
                        ▼                 ▼
                btm_items.csv     btm_items.json
                 full-field table   structured data
                                          │
        btm-view.tpl.html                 │ (3) inject into template
        (page skeleton + JS)  ────────────┤
                                          ▼
                                  btm_items.html
                       table + column picker + 8 trees
```

### 10.2 Three key design decisions

**(1) Why a "lossless TSV" intermediate layer**

Generating CSV and JSON independently from the text would mean writing the field-handling logic twice, and the two would eventually drift (classic symptom: CSV is missing a field JSON has). With a TSV layer in between, all outputs derive from it — **consistency becomes structural rather than a matter of discipline**. It also doubles as the diff tool's input.

**(2) Why derived columns are computed in awk, not in the page**

If classifications like `config_kind` / `exec_scope` were computed only in the page's JS, then "what the table shows" and "what the tree shows" would come from two code paths and could disagree. They are now computed at parse time and stored in columns — **the page merely reads columns**, so the table and the trees cannot drift apart.

**(3) Why field names get "known + unknown" treatment**

BTM is a private interface; Apple can add fields at any time. So the parser keeps a **known-field table** (mapped to canonical column names) and turns everything else into `raw_<original name>` columns. The result: **a new field means an extra column, never lost data**.

### 10.3 How determinism is guaranteed

| Mechanism | Effect |
|---|---|
| Every sort preset ends with `uuid` + `seq` | Removes ordering ambiguity among ties |
| `LC_ALL=C sort` | Immune to locale collation rules |
| Nothing random is emitted | Same input twice → byte-identical `tsv` / `csv` |
| Timestamps only go into `meta.json` / `capture.txt` | Data files stay diffable |

---

## 11. Fields & glossary

### 11.1 Background terms

| Term | Meaning |
|---|---|
| **BTM** | Background Task Management, the macOS subsystem that manages background persistence items |
| **`sfltool`** | A built-in macOS command. `sudo sfltool dumpbtm` exports the BTM database. **Undocumented, no man page**; field meanings come from community reverse-engineering |
| **BTM database** | `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm`. Requires root to read |
| **`dumpbtm` output shape** | Sections per **UID record group** → `Items:` → each record opens with ` #N:` → fields as `Key: value` (names right-aligned to column 21) → optionally followed by an `Embedded Item Identifiers:` sub-list |

### 11.2 Record groups (UID)

| UID | Meaning |
|---|---|
| `-2` | **Composite group.** The dump collects scattered background items here; most "system-level" entries live here |
| `0` | root |
| `501` | Normal user (the first admin account) |

> The same software often appears in both `-2` and `501`. **That is not duplication** — it registered once per scope.

### 11.3 Generation

> **It is not a parent/child generation, and not a "which generation". It is an integer counter BTM keeps per record.**

Apple does not document it, so here it is in two parts:

**What is certain:**
- It is an independent integer per record, **completely unrelated** to the hierarchy described by `Parent Identifier`.
- Different entries of the same software have very different values, indicating it is maintained **per entry**.

**Empirical reading (no official source — treat as "plausible but unproven"):**
- "Each time a record is re-registered, the number goes up."
- Supporting structural observation: `developer` parent records (written once at install time) tend to sit at very low values, while **application entries that re-register login items on every launch are markedly higher**.

**Its real value is the other way round:**

> Because Generation changes on its own, **"only Generation changed" between two snapshots usually does not mean you changed anything**.

The diff tool therefore isolates it as tier 5 rather than mixing it with core fields, where it would wash out real edits.

> ⚠️ **Do not use it for causal inference or security judgement.** "Re-registration increments it" is an empirical reading. To settle the semantics you would need a machine you can reboot repeatedly and observe the delta across several dumps of the same record.
>
> The page's field reference derives this paragraph **from the actual values in your current dataset** rather than hard-coding a number.

### 11.4 Configuration path ≠ executable path

The easiest pair to confuse:

| Field | Question it answers | What it points at |
|---|---|---|
| `URL` → `url_path` | **Where the configuration (plist / app bundle) is registered** | the plist file, or the app bundle / an in-bundle component itself |
| `Executable Path` | **Where the program that actually runs lives** | the binary's real location |

Every record falls into one of three shapes:

| Shape | Explanation |
|---|---|
| Both present | Configuration registered somewhere, plus a standalone executable (daemons and agents are like this) |
| `URL` only | The configuration *is* the payload: login-item helpers, QuickLook extensions, Spotlight importers, apps registering themselves as login items |
| Neither | developer parent records — ownership only, no landing point |

Supporting derived columns (all **classifications**, not judgements):

| Column | Based on | Values |
|---|---|---|
| `config_kind` | `url_path` | system daemon config / global agent config / user agent config / built-in system config / app bundle itself / in-bundle component / other absolute path / other relative path / no configuration path |
| `config_dir` | `url_path` | Directory owning the configuration. **If the path is itself a `.app`, it walks up to the containing directory** — otherwise every app under `/Applications` would become a fake group of one |
| `exec_scope` | `executable_path` | system privileged helper / system app-support dir / other system library location / built-in system / in-bundle (Contents/MacOS) / in-bundle (other) / local install dir (`/usr/local`) / **user home (user-writable)** / relative path / other absolute path / no standalone executable |
| `exec_dir` | `executable_path` | Directory owning the executable (no walk-up, kept verbatim) |

Rule details:

- Order is priority: first match wins.
- A `/Contents/` segment **anywhere** in the path is classified as an **in-bundle component** rather than the app bundle itself — login-item helpers, QuickLook extensions and Spotlight importers all take this form (a relative path, relative to the owning app bundle).
- A leading `./` is normalised before classification, but **the column keeps the original value**.
- The "no configuration path" and "no standalone executable" buckets exist so that **nothing is dropped**, not because something went wrong.

### 11.5 Identifier prefix numbers

Identifiers look like `16.com.example.daemon`; the number before the dot is a scope code matching the `Type` value domain:

| Prefix | Meaning | Hex |
|---:|---|---|
| `2` | app | `0x2` |
| `4` | login item | `0x4` |
| `8` | background agent | `0x8` |
| `16` | daemon | `0x10` |
| `64` | Spotlight plug-in | `0x40` |
| `2048` | QuickLook plug-in | `0x800` |
| (none) | developer parent record, `Identifier` is the developer name | `0x20` |

Split into `identifier_scope` / `identifier_scope_zh` / `identifier_base` so you can aggregate by the prefix-stripped name.

### 11.6 Disposition and Flags

Shaped like `[enabled, allowed, visible, notified] (0xb)`, split into 5 boolean columns: `enabled`, `allowed`, `visible`, `notified`, `hidden` (the inverse of `visible`).

Worth checking are the four combinations of `enabled` and `allowed` for self-contradiction — `enabled + disallowed` or `disabled + allowed` are known database inconsistency states. The "disallowed only" filter is a quick way to sweep for them.

### 11.7 The full 51 columns

<details>
<summary>Expand all columns (click)</summary>

**Record group (5)** — `uid` · `uid_domain` · `group_uuid` · `sm_migrated` · `ls_registered`

**Identity (5)** — `seq` index within group · `uuid` · `name` · `developer_name` · `team_identifier` signing team ID

**Type (4)** — `type_raw` · `type_mechanism` · `type_modifiers` · `type_hex`

**Status (10)** — `flags_raw` · `flags_list` · `flags_hex` · `disposition_raw` · `disposition_hex` · `enabled` · `allowed` · `visible` · `notified` · `hidden`

**Identifier (4)** — `identifier` · `identifier_scope` · `identifier_scope_zh` · `identifier_base`

**Configuration & landing (7)** — `url` · `url_path` · `config_kind` · `config_dir` · `executable_path` · `exec_scope` · `exec_dir`

**Relations (8)** — `bundle_identifier` · `bundle_key` · `parent_identifier` · `parent_kind` · `assoc_bundle_ids` · `assoc_count` · `embedded_item_identifiers` · `embedded_count`

**Change (4)** — `generation` · `dup_group` · `match_key` · `source_line`

**Structure (4)** — `child_count` · `depth` · `node_path` · `persistence_zh`

**Plus** `raw_*` — unrecognised fields become columns automatically; the count varies.

</details>

### 11.8 Other key columns

| Column | Meaning |
|---|---|
| `parent_identifier` | "Who registered me". May point at a developer parent record (e.g. `Example Corp`) or at an app entry (e.g. `2.com.example.toolbox`) |
| `embedded_item_identifiers` | "Which children I embed". This and `parent_identifier` are **two directions of the same relation, and the sets do not fully coincide** — when they disagree, the tool flags it as-is instead of "correcting" it for you |
| `bundle_key` | Grouping key: the record's own `Bundle Identifier` first, then the first `Assoc. Bundle IDs`. Falling back to the identifier base name would shatter developer records and agents into fake single-item groups, so that fallback is deliberately not used |
| `dup_group` | Records in the same UID with an identical "identifier base name + mechanism" share one code. **Nothing is deleted — only flagged** |
| `match_key` | Semantic primary key for cross-snapshot matching (base name | mechanism) |
| `source_line` | Line number of the record in the original dump, for character-level tracing |
| `node_path` | The full ownership chain, e.g. `developer › app › entry` |

---

## 12. Why shell instead of Python

An earlier version was written in Python (standard library only). It had a real weak point: **`/usr/bin/python3` on macOS is a by-product of the Xcode Command Line Tools** — on a machine without CLT, running it pops up an install prompt instead of executing. The whole value of this tool is that it runs "whenever you happen to need it", so removing that dependency is worth it.

Shell reaches feature parity via three choices (mirroring §10.2):

1. **Parsing in awk** — awk's home turf; it just can't discard fields at export time the way the common one-liner scripts do.
2. **All HTML interactivity in the browser** — column picking, sorting, filtering and trees are page JS; the shell only injects JSON.
3. **CSV / JSON both derived from one lossless TSV** — a single intermediate, multiple outputs.

**Trade-offs**: macOS ships BWK awk (not gawk), so the scripts stay within the **POSIX subset** (no `gensub`, no `match` capture groups, no multidimensional arrays), and sorting is delegated to `/usr/bin/sort` rather than hand-written in awk. String comparison uses `LC_ALL=C` for determinism.

---

## 13. Repository layout

```
btm-dump/
├── btm.sh                Main script: capture + parse + emit everything at once
├── btm-extract.awk       (1) parse: dumpbtm text -> lossless TSV (derived cols, sorting)
├── btm-emit.awk          (2) export: TSV -> CSV / JSON / column-name map
├── btm-view.tpl.html     (3) page template (table + column picker + 8 trees + reference)
├── btm-diff.sh           Diff entry point
├── btm-diff.awk          Diff logic
├── btm-selftest.js       Page self-test (development only, needs Node)
├── examples/
│   ├── demo-before.txt   Synthetic example: before (fully fictional)
│   ├── demo-after.txt    Synthetic example: after
│   └── demo-changes.md   Real diff report produced from the two files above
├── README.md             Chinese documentation
├── README.en.md          This file
├── LICENSE               MIT
└── .gitignore            Ignores local capture output such as snapshots/
```

Running `btm.sh` creates `snapshots/<label>-<timestamp>/` (already git-ignored).

---

## 14. Development & self-test

The page interaction logic (table / sort / filter / column panel / 8 trees / collapse / detail / field reference) is covered by an automated test using Node with a minimal DOM stub. Expected strings are **derived from the page's own dictionary** rather than hard-coded in either language; the main run uses the page's default language, then the test switches the same loaded page to English and re-checks:

```zsh
./btm.sh -f examples/demo-before.txt -l t -o /tmp/t
node btm-selftest.js /tmp/t/latest/btm_items.html        # page self-test (includes a language-switch pass)
node btm-selftest.js --i18n btm-view.tpl.html            # dictionary-only check, no snapshot needed
```

Beyond the page self-test, `btm.sh` has two guards of its own that prefer failing to emitting a broken file: after rendering the HTML it asserts both dictionary blocks are present, and after writing the CSV it asserts that the first three bytes really are `EF BB BF`.

The latter came out of a real failure — macOS's `/usr/bin/printf` does not understand `\x` escapes, so `printf '\xef\xbb\xbf'` emits the nine literal characters `xefxbbxbf`. The BOM was purely decorative, Excel showed a polluted first column header, and nothing about the CSV looked wrong on inspection. The fix is to use octal `\357\273\277`.

Assertions are **derived from the data** (not pinned to any one machine's software list), so they hold on a different machine or a different snapshot. Key checks:

- Each tree's item-node count must be **≤ the total record count** (guards against duplicate mounting)
- The configuration tree shows only configuration kinds and the executable tree only executable kinds (**no cross-contamination** — the hard evidence that the two trees really rest on two different fields)
- The record counts of the two "none" buckets must match the number of records with an empty `URL` / `Executable Path`
- **The detail panel must list every group of the record** — also a regression test. Historical bug: the grouping loop read `if (gi > 0 && GROUPS.indexOf(g) >= 0) return;`, which skipped **all** groups but the first, so the panel showed a single "Record group" section and silently swallowed the other 40-odd fields while still looking perfectly normal. The assertion compares group *counts* rather than field counts, so adding a column never causes a false alarm
- **A collapsed node must be expandable again** — a regression test. Historical bug: the original code decided "does this node have children" by asking whether a `.tkids` element existed in the DOM, but that element is not rendered while collapsed, so the UI degraded to "collapse works, expand never does". The fix records "has children" in a `data-kids` attribute. The test was verified against the pre-fix logic to confirm it isn't decorative
- **Kind membership must match the group-label element exactly**, never a bare substring — the English label `Application Support` is also a substring of the directory path `/Library/Application Support/…`, so a naive substring test reports an ordinary path in the configuration tree as "the two trees are cross-contaminated". This one came out of a real failure
- **The two dictionaries must have one-to-one keys**, and the `en` side must contain no CJK or full-width characters (`--i18n` mode). A missing key renders as the key name itself in the page, so this check guards against "added interface text, forgot the other language"
- **Switching language must not lose state**: after switching to English the view, filters, sort, column selection and expanded tree nodes must all survive, and the choice must be written to `localStorage`
- **No Chinese in the English *interface***: 12 rendered views plus every record's detail panel are scanned character by character. Before scanning, **data values are stripped out** — having an app with a Chinese name installed ("坚果云" and the like) is not a translation gap; what matters is the interface text and the enum values that *should* be translated. The 中文 / English toggle buttons are exempt by design (a language names itself)

> Every one of these was checked against a **negative control**: breaking a dictionary key, making the switch reset the expanded state, skipping the `localStorage` write, dropping the enum translation from the detail panel, and reverting the detail grouping loop to its old form — each mutation tripped the matching assertion, confirming the tests are not decorative.

---

## 15. Known limitations

This tool handles **metadata only**. Please note its boundaries:

- **It cannot see binary contents.** It tells you who registered something, who signed it, where the program lives, whether it is enabled — not what code is inside. Confirming suspicious behaviour still needs hashing, signature validation and traffic analysis.
- **It makes no risk judgements.** It reports facts and differences, never "safe / dangerous" verdicts.
- **`Generation` semantics are unproven** — see §11.3.
- **`dumpbtm` is a private interface**; Apple may change the format at any time. If it does, unrecognised fields are still captured into `raw_*` columns (no data loss), but a few derived columns may need adjusting — that means editing the corresponding section of `btm-extract.awk`.
- **`url_path` decodes only `%20` / `%2F` / `%40`**; other percent-escapes are left as-is.
- **The diff tool's key matching is "last one wins"**: if a UID contains twins with an identical `(uid, match_key, executable_path)`, they are separated earlier by the level-1 uuid match, so normal cases are unaffected; a mis-pairing is only possible if both records' UUIDs changed as well.
- **The Chinese column-name map is maintained in exactly one place** (`btm-emit.awk`; `btm-diff.sh` reuses it via `MODE=colmap`). Remember to keep it in sync when adding fields.
- **The English view translates the interface only, never the data.** Language switching has no effect on `tsv` / `csv` / `json`; implementation comments in the template remain Chinese (the template keeps a single copy of the logic rather than being duplicated). The data-side Chinese column names live in `btm-emit.awk`, the interface-side English ones live in the template dictionary (`col.<column>`); the two layers are independent — so a new column means adding one line to each.

---

## 16. License

[MIT](LICENSE)

`sfltool` / BTM is a private Apple interface. This project only parses its **text output**; it calls no private APIs and modifies nothing on your system.

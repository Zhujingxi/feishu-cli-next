# Feishu CLI Next

A Feishu/Lark CLI for AI agents that work through a shell and files. It builds on the official Lark CLI and adds command discovery, compact results, file artifacts, typed data transfer, and mutation recovery evidence.

The goal is to reduce the tokens needed to complete a task while preserving every original command and workflow, data fidelity, and successful outcomes. Results remain task-dependent. The current evaluation targets **more than 50% fewer tokens for Docs read/edit and at least 30% fewer for each other evaluated function versus the original CLI**, with failed-attempt costs included and no observed success regression.

Synced with [official Lark CLI v1.0.97](https://github.com/larksuite/cli/releases/tag/v1.0.97). See the [upgrade comparison and optimization measurements](docs/reference/v1.0.97/OPTIMIZATION.md). The original frozen reference remains available for historical comparisons.

[中文说明](README.zh.md) · [Quick start](#quick-start) · [Usage](#usage) · [Full evaluation matrix](evaluation/evidence/full-matrix-20260911/REPORT.md) · [Implementation status](docs/IMPLEMENTATION.md)

## What this project adds

| Capability | What it provides |
| --- | --- |
| Command discovery | Search registered commands with bounded results; optional flag descriptions expose accepted inputs without a separate help lookup. |
| Compact JSON | Full JSON data in compact form by default; optional indentation and field selection. |
| Docs reads and local edits | Read native text and table relationships, select focused excerpts, or save a compatible working copy for verified text edits across unambiguous formatting boundaries. |
| File artifacts | Save supported read results to versioned, identity-bound files for local processing and handoff. |
| Typed data workflows | Sheets export/import and Base record workflows with validation, type preservation, and operation-specific no-op detection. |
| Mutation evidence | Durable local receipts distinguish rejected, partial, and unknown outcomes without replaying writes. The exact raw Contact basic-profile POST read retains read-only behavior. |
| One entry skill | Install direct routes for common tasks, including local Docs text edits, native XML operations, single-row Base updates, exact Sheets exports and Drive transfers; load deeper guidance on demand. |
| Upstream compatibility | Retain domain shortcuts, generated service commands, raw API access, authentication, events, and the extension SDK. |

The inherited surface includes Docs, Sheets, Base, Drive, Wiki, Contacts, Messages, Calendar, Tasks, Mail, meetings, and other registered services. See the [capability inventory](docs/reference/README.md) and [section evidence](docs/sections/OWNERSHIP.md) for scope and verification status.

**Status:** development distribution. Full live parity and release acceptance remain open. Source builds and local installation are available; a public release/update channel is not configured. Windows execution is deferred. See [distribution details](docs/distribution.md).

## Quick start

Requires **Go 1.26.9+** and `make`. The first build may download Go dependencies. The official v1.0.97 API catalog ships with the source and is embedded directly. Python 3 is needed for inventory, packaging, evaluation, and prefix installation scripts.

```sh
git clone https://github.com/Zhujingxi/feishu-cli-next.git
cd feishu-cli-next
make build
./feishu-cli-next --version
```

Check an existing account configuration:

```sh
./feishu-cli-next auth status
```

For first-time setup, configure your Feishu/Lark app and authorize the user account:

```sh
./feishu-cli-next config init --new
./feishu-cli-next auth login --recommend
```

Authentication reuses upstream profiles, credential providers, brand selection, and `LARKSUITE_CLI_*` settings. User and bot identities have different permissions. See [authentication and setup](README.upstream.md#authentication) for scope and account options.

Install the entry skill into an existing agent project:

```sh
./feishu-cli-next guide install --project /path/to/your/project
```

This writes the CLI-owned skill under the project's `.agents/skills/` directory. `guide update` and `guide uninstall` manage that installation. To put the executable on your path, use `make install PREFIX="$HOME/.local"` and include `$HOME/.local/bin` in `PATH`; use the same prefix for `make update-install` or `make uninstall`.

## Usage

Use a known command directly. Help, discovery, and schema inspection are available when needed:

```sh
# Inspect one domain or search for a command.
./feishu-cli-next contact --help
./feishu-cli-next discover 'contact open_id' --flags --limit 3
./feishu-cli-next schema drive files list

# Search for a user or a visible bot using user identity.
./feishu-cli-next contact +search-user --query 'Alex' --as user
./feishu-cli-next contact +search-bot --query 'assistant' --as user

# Read document facts as Markdown with native block IDs.
./feishu-cli-next docs +pull --doc DOCUMENT_TOKEN --as user

# Export an explicit Sheets range to a local artifact.
./feishu-cli-next sheets +data-export \
  --spreadsheet-token SPREADSHEET_TOKEN --sheet-id SHEET_ID \
  --range A1:E100 --save-result cells.json --as user
```

For a generated method's request requirements, use `schema <service.resource.method> --input-only`.
It retains the full input schema, permissions, risk and command guidance while
omitting the response schema. Omit the flag when you need response field definitions.

Replace resource placeholders with your own IDs. Discovery describes the local command surface; access still depends on the selected account and scopes. Shortcuts start with `+`; generated service commands expose catalog methods, and `api` provides raw OpenAPI access.

### Read focused Docs content

Without `--output`, `docs +pull` returns a read-only Markdown view with native anchors, readable lists, tasks, code, quotes, deeper headings and table/cell relationships. Unsupported content stays visibly labeled. Tables retain native cell order and content links; the CLI does not invent coordinates or merged-cell geometry. Contradictory table/list parent-child relationships are rejected before output.

```sh
./feishu-cli-next docs +pull --doc DOCUMENT_TOKEN --scope keyword --keyword 'budget' --as user
./feishu-cli-next docs +pull --doc DOCUMENT_TOKEN --scope outline --as user
./feishu-cli-next docs +pull --doc DOCUMENT_TOKEN --scope section --start-block-id HEADING_ID --as user
./feishu-cli-next docs +pull --doc DOCUMENT_TOKEN --scope range --start-block-id FIRST_ID --end-block-id LAST_ID --as user
```

Keyword search is literal, case-insensitive and confined to individual native text blocks. Sections end before the next heading of equal or higher level; range bounds are inclusive. Selection runs locally after reading the complete native snapshot. Check `returned_blocks`, `total_blocks` and `complete`; a complete block selection does not make opaque content readable. A missing keyword match does not prove absence from opaque content. Scoped results cannot be saved as editable working copies. Existing server-scoped `docs +fetch` remains available.

### Edit Docs through a local working copy

```sh
./feishu-cli-next docs +pull --doc DOCUMENT_TOKEN --output note.md --as user
# Edit supported text in note.md; keep its block markers and formatting intact.
./feishu-cli-next docs +push --file note.md --dry-run --as user
./feishu-cli-next docs +push --file note.md --as user
```

Pull with `--output` requires full scope and preserves the original v1 editing projection, including opaque unsupported regions. It creates `note.md` and its identity-bound `note.md.feishu.json` native sidecar without overwriting either file. Existing saved workspaces remain compatible; keep both files together. Push validates the entire local edit plan, checks current native state, and changes supported paragraph and heading text while preserving its existing styles and link destinations. Multiple native text runs can change when unchanged formatting uniquely separates them; adjacent unmarked runs or ambiguous boundaries are rejected rather than assigned guessed styles. Its compact result includes `verified` and complete `changed_blocks` texts with native IDs. An unchanged working copy produces no content write. Pull to a fresh path before making further edits after a push.

This is a text-editing workflow, not a universal Markdown round trip. Unsupported structural or formatting changes stop before writing. Existing `docs +fetch`, `docs +update`, native block operations, media commands and Drive import remain available for rich documents and other original workflows. See the [local Docs guide](skills/lark-doc/references/lark-doc-workspace.md).

Snapshot checks detect observed conflicts but cannot close the race with a concurrent writer; the native revision parameter is not compare-and-swap. Unknown or partial outcomes require reconciliation, not a blind push retry. The [final private native lifecycle](evaluation/evidence/docs-improvements-native-live-final-20260909.json) passed nine checks on candidate `cad221e`: rich/focused reads, compatible saved-view no-op, and three text-run edits across two blocks with exact original-CLI comparison of styles, links, IDs and remaining native content. Its one run-owned private document was confirmed deleted. This bounded native test does not measure token savings or establish every rich-document or concurrency case.

### Results and recovery

- `--result-detail` indents JSON. `--result-fields id,name` selects supported result fields while retaining outcome and completeness metadata. Domain flags such as `--fields` and `--detail` keep their original meanings.
- `--save-result PATH` saves the full result for supported reads without overwriting an existing file. These artifacts have domain-specific contracts; a saved envelope is not a raw API request body. See the [output contract](docs/contracts/output.md).
- Check both the JSON outcome and process exit status. A timeout after a write may leave its effect unknown. `receipts list` and `receipts inspect ID` expose local attempt evidence for reconciliation. See the [receipt contract](docs/contracts/receipts.md) before retrying an uncertain mutation.

### Why the old skills remain

[`agent-skills/feishu-cli-next/SKILL.md`](agent-skills/feishu-cli-next/SKILL.md) is the entry skill installed by `guide install`. The inherited [`skills/`](skills) directory supplies compatibility documentation and detailed references used by help and `skills read`.

Those guides are not all injected by installing the entry skill. They can still influence an agent and consume context when it reads them on demand. The evaluation includes that work; Next did call `skills read` in some trials. Upstream examples use `lark-cli`; use `feishu-cli-next` with this distribution.

## Evaluation results

The [October 7 local CLI probes](evaluation/evidence/cli-efficiency-20261007/REPORT.md)
measure request-only schema context size and discovery latency. They are local
introspection measurements; the full-task results below remain unchanged.

### Full matrix

The [automatic full matrix](evaluation/full-matrix.md) completed all **43 implemented development tasks / 258 attempts** across paired functions, harder Docs, domain reads, workflow scenarios, scaling, business, foundation and Contact. The [completed matrix report](evaluation/evidence/full-matrix-20260911/REPORT.md) includes **240 new attempts and all 18 reviewed condition 09 attempts reused unchanged**. The per-task target remains **unmet: 13 gates met, 22 missed and 8 unavailable**.

| Full-matrix result | Original | Next |
| --- | ---: | ---: |
| Verified / attempts | 102/129 | 107/129 |
| Inconclusive | 2 | 0 |
| Observed provider tokens (lower bound) | 17,597,508 | 14,954,750 |

**Six attempts lack complete usage**, so both whole-matrix tokens-per-success savings and raw token-spend reduction are **unavailable**. Known usage totals **32,552,258 tokens**: **31,650,572 new** and **901,686 reused historical tokens**, not new spend. Every recorded failure and recovery cost remains included. The [fixture qualifications](evaluation/evidence/full-matrix-20260911/QUALIFICATIONS.md) explain strict route failures despite correct answers; these counts do not establish live reliability or universal savings. An [independent final audit](evaluation/evidence/full-matrix-20260911/result-review.json) accepted the retained accounting and report claims.

After preparing the [local path configuration](evaluation/README.md#automatic-full-matrix), run:

```sh
python3 evaluation/run_matrix.py --config /absolute/local-config.json \
  --output evaluation/evidence/full-matrix-20260911 --execute
```

The command skips unchanged completed results, including failures and inconclusive outcomes, and resumes validated checkpoints. It also reuses matching sealed, complete jobs from sibling output directories under the same parent; this is not a machine-wide cache. Reuse requires identical measured inputs, including the Python executable/version. It never automatically repeats an unresolved in-flight attempt. Omit `--execute` to validate inputs and regenerate the report without model calls. Changed measured inputs require a new output directory. [Configuration, reuse, interpreter pin and resume details](evaluation/full-matrix.md).

The report's suite/task tables separate coverage, verified outcomes and each function's gate. Pooled spend cannot replace the strict Docs >50% or other-task ≥30% targets. Three repetitions per arm and bounded synthetic fixtures do not establish statistical success parity or exhaustive live functionality.

### Completed condition 09

**[Completed condition 09: harder Docs workloads →](evaluation/evidence/token-efficiency-09/REPORT.md)**

Condition 09 completed **18 fresh attempts: Next 9/9 verified, original 8/9 verified and one inconclusive**. It used **GPT-5.6 Luna with medium reasoning through native Codex CLI 0.153.4**, comparing candidate `cad221e` against the original CLI. The strict **>50% saving per task remains unmet: zero gates met, two missed and one unavailable**.

| Task | Tokens per verified success vs original | Original verified/attempts | Next verified/attempts | Gate |
| --- | ---: | ---: | ---: | --- |
| Read tables and lists | 38.2% less | 3/3 | 3/3 | Missed |
| Focused retrieval from a larger document | 31.1% less | 3/3 | 3/3 | Missed |
| Multiple styled wording edits | Unavailable | 2/3; one inconclusive | 3/3 | Unavailable |

All provider usage was complete: **901,686 tokens**, including **185,209** from the inconclusive original editing attempt. Its strategy exceeded the fixture's supported coverage; the missing comparison is not scored as a product failure or a zero-cost success. All attempt and recovery costs remain included. Both arms read full selected guidance from files inside the measured loop.

These are three harder Docs tasks with three repetitions per arm; no other functions were measured. They differ from condition 08's tasks, so its historical **56.8% combined Docs saving** is not a direct before/after comparison with this candidate. The observed counts do not establish statistical success parity, stable savings or exhaustive live functionality. Native lifecycle checks remain separate evidence. [Protocol](evaluation/token-efficiency-09.md) · [Exact results and accounting](evaluation/evidence/token-efficiency-09/summary.json).

### Historical condition 08

**[Historical condition 08 →](evaluation/evidence/token-efficiency-08/REPORT.md)**

Historical condition 08 verified **12/12 attempts: original 6/6 and Next 6/6**, using **GPT-5.6 Luna with medium reasoning through native Codex CLI 0.153.4**. The strict per-function target remains **unmet**: Docs edit passed, Docs read missed, and the declared stop rule left **36 attempts across six other functions not run**.

| Function | Tokens per verified success vs original | Original verified/attempts | Next verified/attempts | Gate |
| --- | ---: | ---: | ---: | --- |
| Docs read | 44.3% less | 3/3 | 3/3 | Missed |
| Docs edit | 61.1% less | 3/3 | 3/3 | Met |
| Other six functions | Not measured | Not run | Not run | Not measured |

**Secondary combined Docs workload: 56.8% fewer tokens**, from **472,979 original** to **204,413 Next**, with both arms **6/6 verified**. This totals three read and three edit attempts per arm, weighting the more expensive edits more heavily. It does **not** satisfy the separate >50% read gate or establish savings for other task mixes.

All usage was complete, totaling **677,392 tokens across both arms**. Every attempt and recovery cost is included. Both arms received their selected skill by file path and were instructed to read it within the measured tool loop. Next's entry guide also became shorter; its runtime, native fidelity checks and original command surface stayed unchanged. Because guidance length and delivery both changed, earlier-condition differences cannot isolate either factor. These small development samples do not establish statistical success parity or full live functionality. [Protocol](evaluation/token-efficiency-08.md) · [Stage decision](evaluation/evidence/token-efficiency-08/stage-decision.json).

Historical [condition 07](evaluation/evidence/token-efficiency-07/REPORT.md) retained 11/12 verified attempts, 36.1% Docs-read savings and 67.0% Docs-edit savings; original edit verified 2/3 versus Next 3/3. [Condition 06](evaluation/evidence/token-efficiency-06/REPORT.md) retained 12/12 verified, 1.0% more read tokens and 42.1% fewer edit tokens. Both stopped before the other six functions; neither is pooled with condition 08.

**Qualification for conditions 05/06:** a later no-model native control found that disabled-skill directory paths left eight public `CODEX_HOME` catalog entries advertised; exact `SKILL.md` paths suppressed them. Both arms shared the affected configuration. Corrected suppression is retained in condition 08. The probe does not quantify billed-token impact or establish a cause for file-read loops. [Qualification and evidence](evaluation/evidence/token-efficiency-05-06-skill-isolation-qualification.md). Historical results remain unchanged.

### Previous full comparison: condition 05

**[Read condition 05 →](evaluation/evidence/token-efficiency-05/REPORT.md)**

The target was **not met: 3/8 functions met their gate, 3 missed and 2 were unavailable**. Condition 05 completed 48 fresh attempts against the original CLI: eight tasks, three repetitions, two arms, using **GPT-5.6 Luna with medium reasoning through native Codex CLI 0.153.4**. The benchmark uses signed synthetic Feishu fixtures; private native QA is separate evidence.

**40/48 attempts verified: Next 22/24, original 18/24.** Docs edit regressed from original 3/3 to Next 2/3. Observed provider usage was **3,602,432 tokens, a lower bound** because four Drive attempts had incomplete usage.

| Function | Tokens per verified success vs original | Gate |
| --- | ---: | --- |
| Discovery | 14.8% more | Missed |
| Contact search | 58.2% less | Met |
| Docs read | 6.4% less; both 3/3 verified | Missed |
| Docs edit | 172.0% more; Next 2/3 vs original 3/3 | Missed |
| Markdown creation | 60.7% less | Met |
| Base update | 36.6% less | Met |
| Sheets export | Unavailable: original 0/3 verified | Unavailable |
| Drive roundtrip | Unavailable: incomplete usage and original 0/3 | Unavailable |

The primary gate requires strictly more than 50% savings for Docs read/edit and at least 30% for each other function, with no observed success regression. All attempt costs, including failures and recovery, count toward tokens per verified success. Cached input is counted once; missing usage is never zero. These small development samples do not establish stable savings, statistical success-rate parity or full live functionality.

Docs-edit traces show rejected `+push` calls followed by `+update` fallback. The retained traces omit local file contents and validation-error text, so they do not establish the rejection's exact cause. The failed result and fallback costs remain included.

[Frozen environment](evaluation/evidence/token-efficiency-05/environment.json) · [Readiness review](evaluation/evidence/token-efficiency-05/readiness-review.json) · [Protocol](evaluation/token-efficiency-05.md) · [All evaluation conditions](evaluation/README.md)

Historical [condition 04](evaluation/evidence/token-efficiency-04/REPORT.md) remains a separate exploratory comparison: 24 new candidate attempts, 48 reused baselines and 5/8 gates met against unchanged Next. Its 50% target and reused-baseline results do not satisfy condition 05's original-CLI comparison. Earlier [pilot 01](evaluation/evidence/paired-luna-medium-01/REPORT.md), [condition 02](evaluation/evidence/token-efficiency-02/REPORT.md) and [condition 03](evaluation/evidence/token-efficiency-03/REPORT.md) retain all their costs, failures and accounting limits.

## Development

```sh
make build
make evaluation-test   # Isolated harness tests; no model trials.
make next-script-test  # Isolated tooling tests.
make unit-test
make vet
make fmt-check
```

`make test` runs the broader suite. Section and integration runners record pass/fail/skip evidence while isolating developer configuration. Live tests require their documented fixture prerequisites. See [test isolation](tests/next_foundation/README.md), [evaluation tooling](evaluation/README.md), and [contributor instructions](AGENTS.md).

Project documentation:

- [CI execution](docs/ci.md) — self-hosted Linux routing, prerequisites and queued-job recovery.
- [Implementation ledger](docs/IMPLEMENTATION.md) — completed work, evidence, and remaining gates.
- [Design plan](docs/PLAN.md) — goals, scope, and acceptance criteria.
- [Distribution](docs/distribution.md) — local installation, packaging, and release status.
- [Contracts](docs/contracts) — output, artifacts, receipts, and skill lifecycle.

## Upstream and license

This is a separate development distribution derived from `larksuite/cli` at commit `7fd6ef3c07182257ce776cdc5a614e122d5bd4b3`, not an official Lark release. The Go module remains `github.com/larksuite/cli` for source and extension compatibility. Original copyright notices, the [MIT license](LICENSE), and [upstream documentation](README.upstream.md) are retained.

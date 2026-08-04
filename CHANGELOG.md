# Changelog

## 2026-08-04

### Added
- **`tools/mirror-to-public.sh`** — the sync from the maintainer's private `~/.kiro` to this sample, encoded rather than improvised. It applies the standing transformations (orchestrator name; the steering, hook-script, and gate-command path forms that differ because the private tree *is* `~/.kiro` while this one is cloned to `<project>/.kiro`) and refuses to touch four files that diverge on content. `--check` reports drift without writing; `--self-test` covers every transformation plus two cases that must be left alone.

  It exists because the sync was being done by hand and overwrote a deliberate divergence: this repo's `skills/aws-technical-docs/SKILL.md` links the public AWS style guide, and a bulk mirror replaced that with a path to a PDF that only exists in the maintainer's config. It was caught reading a pre-commit diff, which is not a control.

  Writing it found a second bug of the same kind: applying the steering-path rewrite globally corrupts `tools/check-steering-allocation.sh`, whose self-test fixtures deliberately contain the home-absolute prefix to represent "the other tree's form". Rewriting those would make the wrong-prefix test compare a value against itself and silently stop testing anything. The transformations are now scoped by file type, with a self-test assertion pinning that fixture.

### Changed
- **The workflow moved out of `.kiro/specs/` and off the word "spec".** Kiro CLI now ships native specs: the engine owns `.kiro/specs/{feature_name}/` and expects `requirements.md`, `design.md`, `tasks.md` in it — 68 references in the agent server, plus a directory scanner and the task provider whose `updateTaskStatus` call fires the `PreTaskExec` hook. This workflow was putting its own `spec.md`, `tasks.md`, `review.md`, and `security-review.md` in that same tree: same directory, same filename, different semantics. The collision was not theoretical — it sent a hook-gate design astray for an hour, because "does marking a task fire `PreTaskExec`?" has different answers for native specs and for this workflow.

  | Was | Now |
  |---|---|
  | `.kiro/specs/<slug>/` | `.kiro/delivery/<slug>/` |
  | `.kiro/specs/currentspec.md` | `.kiro/delivery/current.md` |
  | `steering/spec-workflow.md` | `steering/delivery-workflow.md` |
  | `spec.md` | `plan.md` |
  | `docs/example-spec/` | `docs/example-plan/` |
  | "spec", "spec-driven" | "plan", "plan-driven" |

  `tasks.md`, `review.md`, `security-review.md`, `design-review.md`, `decisions.md`, `requirements.md`, `epic.md`, `prd/`, and `phases/` keep their names — filename collisions stop mattering once the directory differs, and renaming them would be churn for no benefit. `.kiro/issues/` is untouched; the engine does not own that name. `delivery` was chosen against the engine's own constants, which show the taken names as `steering`, `skills`, `specs`, `agents`, `hooks`, `extensions`, and `powers`.

  The vocabulary pass was done with targeted phrase replacements rather than a blanket substitution, because 555 occurrences of `spec` include SDK specs, API specifications, "spec compliance" in the reviewer checklist, and native-spec references that must survive. Every remaining occurrence was reviewed individually.

## 2026-07-28

### Added
- **`docs/example-spec/` — a complete worked example.** A prototype-depth spec for a FastAPI task API with every artifact the workflow produces: `spec.md`, `design-review.md`, `review.md`, `security-review.md`, and `decisions.md`, each showing two cycles from FAIL to PASS. It also demonstrates the force-upgrade safety floor in practice — the spec is prototype depth, which does not normally gate on security, but the API is an unauthenticated HTTP listener, so network exposure trips the floor and both security gates become mandatory. All three review files parse correctly under `check-review-verdict.sh`.
- **Per-agent steering allocation.** Each subagent declares an explicit list of the steering files it needs instead of loading all nine via a glob. The orchestrator keeps both globs, since it is the only agent that reads project-level `.kiro/steering/`. Mapping and rationale in [docs/agent-design.md](docs/agent-design.md).
- **`tools/check-steering-allocation.sh`** — static check that no steering file uses `inclusion: always`, that the orchestrator declares both required steering globs (and no other agent declares any), and that the allocation matches the published table. Carries a `--self-test` (9 synthetic trees) and documents the runtime check it cannot perform.
- **`tools/check-review-verdict.sh`** + `test-check-review-verdict.sh` (26 cases) — replaces the review-gate `grep`, which could not fail. The check scopes to the newest cycle heading, so a freshly opened cycle with findings but no verdict yet cannot inherit the previous cycle's PASS. A PASS must be a declared verdict — the outcome has to follow the label — and fenced blocks are excluded, so neither reviewer prose nor a quoted template can open the gate.
- **`--self-test` on `check-rule-copies.sh`** — mutates a copy in a temp tree and requires the check to catch it.
- **`tools/check-hook-paths.sh`** — asserts every hook manifest's `action.command` uses the workspace-relative `.kiro/hooks/scripts/` prefix, names a script that exists, and that the script is executable. `--self-test` proves it rejects a manifest reverted to `~/`, a missing script, and a non-executable one. Exists because the manifests shipped with absolute paths that did not resolve under the documented install, and nothing caught it.
- **Security-review gate task template** in `steering/spec-workflow.md`. One existed for the review gate but not for the security gate.

### Changed
- **`settings/permissions.yaml` is now zero-ask: not one `ask` rule remains.** Every rule that used to prompt is now `allow` or `deny`. The reason is mechanical — the engine's decision function returns `reject` with a *reason* for `deny` (the agent is told and keeps working), returns `accept` silently for `allow`, and only for `ask` does it block on a human. So `ask` makes unattended operation impossible by construction: one recursive delete in a scratch directory parks the run until someone clicks. In practice 39 of 645 logged shell calls were resolving to `ask`, and the dominant cause was `rm -r*` — compound commands are split per sub-command, so any long pipeline that merely *contained* a recursive delete matched. This change is stricter, not looser: an `ask` on `rm -rf ~/important` is a prompt a tired operator approves, while a `deny` is a refusal. Two accepted consequences are documented in [docs/permissions.md](docs/permissions.md): some legitimate idioms (`cd /tmp && rm -rf build`, `rm -rf "$T"`) are refused because no shell pattern can resolve them, and the guard hooks now carry more weight — they never prompt, being subprocesses rather than tool calls. `steering/cli-execution.md` gains a *Scratch space and deletes* section telling agents to create scratch with `mktemp -d` and leave it, which removes the need for the denied operation. `fs_write` denies now cover workspace secrets and narrow the old blanket `~/.kiro/**` prompt to the three directories that define what an agent may do (`settings/`, `hooks/`, `agents/`), leaving `steering/`, `skills/`, and `docs/` writable.
- **Hook manifests now invoke their scripts by workspace-relative path** (`.kiro/hooks/scripts/…` instead of `~/.kiro/hooks/scripts/…`), matching the documented install: clone this repo into `<project>/.kiro`. Hook commands run with `cwd` set to the workspace root, so this resolves out of the box and **the symlink step is gone from Quick Start**. Verified against the shipped agent server rather than inferred: `CommandAction.execute` spawns with `cwd: opts.cwd`, and that `cwd` is `workspacePaths[0]`. The same investigation corrected a false claim in `docs/global-config.md` — the engine's `globalHookRoots` is always the home directory, so `~/.kiro/hooks/` loads in *every* workspace and never needed per-project symlinking. Going global now means rewriting the 8 manifests to absolute paths, for which that page supplies a tested one-liner. (`issues/` is not published with this sample, so the investigation notes stay local.)
- **All nine steering files now carry no `inclusion:` frontmatter.** They were `inclusion: always`, which injects every file into every agent regardless of its `resources:` list — confirmed by an agent that declared six files and received all nine. They were then switched to `inclusion: manual`, which turned out to mean *never injected at all*: naming a file in `resources:` does not count as activation, so for a period every agent ran with zero steering while the lists, docs, and checker all claimed otherwise. Isolated with a three-way probe (no frontmatter / `always` / `manual`, all three named in an agent's resources): the first two were delivered, the third was not. No key is the working state. `tools/check-steering-allocation.sh` now fails on any `inclusion:` key, with self-test cases for both values.
- **The orchestrator prompt now covers the gates it dispatches.** It was missing the security-review step from Phase 2, the security design gate from Phase 1, depth selection, `design-review.md` and `security-review.md` from its state files, and security findings from its completion criteria — while being the only agent that runs gates.
- **`patch` depth reconciled across five sources** that previously disagreed. Canonical: `patch` produces no spec and routes to `.kiro/issues/` + `diagnose`, but still runs both review gates. It is low-artifact, not low-scrutiny. The gate matrix, `depth-levels.md`, `README.md`, and `agent-design.md` all said otherwise in different ways.
- **`docs/agent-design.md` savings figures corrected.** Earlier drafts claimed 84% for `docs` and that savings compound across every agent. After restoring the steering files agents actually need, `coder` and `ops` see no reduction, `reviewer` 3%, `security-reviewer` 28%, and `docs` 24%. The page now states which two settings the reductions depend on.
- **`README.md` Quick Start** no longer instructs `cd .kiro` before starting a session, which would have made every workspace-relative resource path and hook discovery resolve to `.kiro/.kiro/`.

### Fixed
- **The three shell hooks never fired on the engine's canonical tool name.** Their matcher was `shell|execute_bash`, but the shell tool's real id is `run_command` — `class _ExecuteBash { static id = "run_command" }` in the agent server, with `execute_bash` as a legacy alias. Any call reported under the canonical id therefore slipped past `00-guard-destructive-commands`, `03-guard-config-writes`, and `50-rtk-compress`. Observed in engine logs as 32 `toolId=run_command` events. Matchers widened to `shell|execute_bash|execute_cmd|run_command`. Note the limitation: matcher evaluation happens engine-side, so the committed suites — which feed the scripts synthesised events directly — cannot prove the regex now matches. Confirm live by watching `50-rtk-compress` act on a subagent's shell call.
- **The mandatory review gate could not run unattended.** Its `Verify` command was `bash ~/.kiro/hooks/scripts/check-review-verdict.sh …`, and `settings/permissions.yaml` has a `shell: ask` rule matching `*.kiro/hooks*` so that editing the enforcement surface requires a human keystroke. Shell patterns support only `*` and cannot tell a read from an execute, so every reviewer and security-reviewer that reached its verdict step prompted mid-review — traced in the engine log as 22 consecutive `toolId=run_command` approval requests, none of them a `subagent` capability. The four scripts that are **not** hooks (`check-review-verdict.sh`, `check-steering-allocation.sh`, `check-rule-copies.sh`, `test-check-review-verdict.sh`) now live in `tools/`, so the gate command no longer contains `.kiro/hooks`. No manifest ever referenced them, so `hooks/scripts/` was the wrong home regardless. The alternative — an `exclude` carve-out on the guard rule — was rejected because the wildcard needed to admit the gate's file argument would also admit a chained command after it.
- **`check-steering-allocation.sh` crashed on any non-markdown file in `agents/`.** It parsed every directory entry as YAML frontmatter, so adding something like `agent_config.json.example` produced an `IndexError` instead of a verdict. It now considers `*.md` only.
- **The trusted-subagent list was lost in the v3 migration.** The v2 configs carried it as `toolsSettings.subagent.trustedAgents`; the migration to v3 markdown agents dropped the block, leaving `subagent` granted as a bare capability that names no agents. Restored as `{ capability: subagent, effect: allow, match: [coder, docs, ops, reviewer, security-reviewer] }` — the shape the engine's own v2→v3 converter emits for `trustedAgents`. Additive, and cannot weaken the policy since resolution is deny > ask > allow. To be clear about what this did **not** fix: the per-spawn approval prompts had a different cause entirely (the gate command matching the config-path `shell: ask` rule — see below). Engine logs show `invoke_subagent.starting` never triggers an approval request; all 22 in the sample were `toolId=run_command` under the `shell` capability. This rule restores parity with the v2 config; it was not the fix for the prompting.
- **`coder` and `reviewer` declared steering with the wrong path prefix and would have loaded no rules at all.** Both kept the maintainer's home-absolute form (`file://~/.kiro/steering/…`) while `docs`, `ops`, and `security-reviewer` used the project-relative form this repo's install produces. Because `chat.disableInheritingDefaultResources: true` makes an explicit `resources:` list restrictive rather than additive, an unresolvable list is an empty list — so the agent that writes code and the agent that reviews it would each have run with no pinning rule, no non-interactive rule, no testing floor, and no `spec-workflow.md`, which is where the safety floor and both mandatory gates live. Found by the security review gate. `check-steering-allocation.sh` had reported both as correct, because it resolved basenames and discarded the prefix; it now requires all five subagents to agree on one prefix and carries a self-test case for it.
- **`dependency-versions.md` added to `docs`.** It was the only agent chartered to document dependencies and installation without the pinning rule, and no hook covers that gap — `check-dependency-pins` inspects only manifest-shaped filenames and `check-secrets` skips `.md` entirely. `docs` now loads 5 files (24% reduction, previously reported as 28%). Why it still does not load `virtual-environments.md` is stated in [docs/agent-design.md](docs/agent-design.md).
- **The review-gate verdict check missed the heading form the design gate mandates.** The cycle scoping matched only `## Cycle N`, so `## Security Design Review — Cycle N` — the heading `steering/spec-workflow.md` requires — fell through to a whole-file scan and reinstated exactly the stale-PASS inheritance the check exists to prevent. `# Cycle N` and `## Cycle4` failed the same way. It now matches the word anywhere in any ATX heading.
- **A sentence of reviewer prose could override a verdict.** `tail -1` took the last line beginning with the word "Verdict", so `Verdict rationale: recommend PASS once the fixes land` written after `### Verdict: FAIL` opened the gate. Declared verdicts (heading or bold form) are now preferred, the loose form is a fallback, and fenced code blocks are excluded so a quoted template is not read as a ruling.
- **The gate's `Verify` command exited 127 in every project.** It mixed a project-relative spec path with a cwd-relative script path, so it only ran from inside the config tree — meaning no verdict was ever read, and a PASS and a FAIL were equally unverifiable. Now uses the absolute `~/.kiro/hooks/scripts/` path, which resolves under both install layouts.
- **The review gate's `Verify` command could not fail.** `grep -i 'verdict.*pass' review.md` matched a stale cycle-1 PASS in an append-only file, and matched the unfilled template line `### Verdict: PASS | FAIL`. Both reproduced.
- **`check-rule-copies.sh` checked the wrong tree.** It hardcoded `~/.kiro`, so running it from a clone verified the maintainer's private config and reported OK while checking nothing about the clone.
- **Every runnable command in `docs/observability.md` was broken** — all used the pre-v3 `~/.kiro/sessions/cli/` path, which matches nothing on a v3 install. The same page claimed a 10-iteration review cap that annotates and continues; the actual rule is 3 cycles then halt and escalate.
- **`chat.defaultAgent` does not exist.** `settings/cli.json` ships feature toggles only, with no default-agent or model key. The README asserted it twice.
- **Public `skills/aws-technical-docs`** pointed at a private-only PDF; now links the public AWS style guide.
- **`docs/mcp-servers.md`** claimed `aws-knowledge-mcp-server` is used by all agents; `docs` declares `mcpServers: {}`.
- **`docs/permissions.md`** contradicted the shipped policy on `list_directory` failing closed and on `builtin: allow` covering shell.
- **`docs/depth-levels.md`** omitted **authorization** from the safety-floor trigger list, described the floor as automatic detection when it is a rule the agent applies, and understated `production` depth (missing the product gate, `epic.md`, `phases/`, the two-part design gate, and the operational-readiness gate).
- **`skills/design`** described the production design gate as one part when it is two — `reviewer` in design mode was never invoked, silently skipping the architecture and feasibility half.
- Pointers to a nonexistent "README Permissions section" in `CHANGELOG.md` and `settings/permissions.yaml` now resolve to `docs/permissions.md`.

## 2026-07-26

### Added
- **Optional `Goal` field on tasks** (`steering/spec-workflow.md`) — a single command whose success is a sufficient definition of done, so Kiro's `/goal` loop can be pointed at one task and left to run. The stop condition must be a command exit code, never a judgment. `/goal` is explicitly forbidden on the review and security-review gates (a verdict is a judgment, and the gates' value comes from a fresh-context agent that did not write the code) and on whole specs or task groups (its loop competes with `execute`'s, and can halt mid-group or iterate past a FAIL verdict the 3-cycle safeguard requires escalating).
- **`/goal` guidance in the `diagnose` skill** — step 4 is the best fit in the workflow, because the failing test is written before the fix and by a different step than the one being verified, so it does not inherit the implementation's assumptions the way a self-authored suite does.

### Changed
- **`settings/permissions.yaml` now warns that its own comments are transient.** Answering an approval prompt with "always allow" makes the CLI rewrite the file and strip every comment — observed on the maintainer's config, where one click deleted 54 lines of rationale while leaving all rules intact. Appended `allow` entries cannot weaken the policy (`deny > ask > allow`), but the reasoning does not survive, so [docs/permissions.md](docs/permissions.md) is now the durable copy. Neither the `guard-config-writes` hook nor the config-path `shell: ask` rule prevents this, since both guard agent writes rather than the CLI's own persistence path.

## 2026-07-24

**Major refactor**: Consolidated steering from 14 to 9 files, migrated workflows to skills, introduced naming framework, added security design gate, and retiered agent models.

### Added
- **Naming framework** — artifact types now inferable from filenames: workflow skills are bare imperative verbs (`design`, `execute`, `diagnose`, `flywheel`, `harvest-debt`); capability skills use `domain-activity` format; steering rules are bare domain nouns. See `CONTRIBUTING.md` for details.
- **Security design gate** (`steering/spec-workflow.md`) — `security-reviewer` gains a design-review mode that evaluates Threat Model sections before implementation begins. Mandatory at `production` depth and whenever a spec touches auth/authz/secrets/data/network (the force-upgrade safety floor). Does not replace the code-level security review; both gates run.
- **Spec depth scaling** in `steering/testing.md` — test ceremony scales with `depth:` level. The runnable-check floor is non-negotiable at all depths.
- **Two new enforcement hooks** — `02-guard-secret-reads.json` and `03-guard-config-writes.json` harden the control surface. Three committed test suites (`test-guard-secret-reads.sh`, `test-guard-config-writes.sh`, `test-write-guards.sh`) with 96 combined test cases ensure the guards work on any machine.
- **`skills/design/`** — interactive spec drafting for all four depth levels (renamed from `scope`).
- **`skills/iac-verification/`** — gained the post-deploy smoke-test obligation and prerequisites from `steering/deploy-validation.md`.
- **`skills/diagnose/`** — gained the issue-tracking templates and the mandatory review/security-review gates after fixes from `steering/issue-tracking.md`.

### Changed
- **Steering consolidated 14 → 9 files**. Merged `non-interactive.md` into `cli-execution.md`, `sdk-verification.md` into `doc-research.md`. Moved `issue-tracking.md` → `skills/diagnose/`, `deploy-validation.md` → `skills/iac-verification/`, `v3-hooks.md` → `docs/v3-hooks.md` (reference, not always-on). Retired: `non-interactive.md`, `sdk-verification.md`, `issue-tracking.md`, `deploy-validation.md`. These nine remain: `spec-workflow.md`, `artifact-locations.md`, `cli-execution.md`, `doc-research.md`, `minimalism.md`, `virtual-environments.md`, `documentation.md`, `testing.md`, `dependency-versions.md`.
- **Agent retiering** — reversed MiniMax assignment; models now: architect/reviewer/security-reviewer on `claude-opus-5`, coder/ops on `claude-sonnet-4.6`, docs on `claude-haiku-4.5`. The task contract updated for Sonnet 4.6's self-verification capability: state intent and interfaces, skip the exhaustive inline restatement.
- **Hooks revised** — two hooks had never fired: `check-secrets` and `check-dependency-pins` read `tool_input.content`; write tools send `text`/`newStr`. Fixed to read all field shapes. Added `fs_append` to both matchers. Added `02-guard-secret-reads.json` and `03-guard-config-writes.json`; deleted `72-doc-update-check.json` (documentation is now a mandatory final group in every spec).
- **Permissions.yaml clarified** — documented the deliberate absence of `fs_read` deny rules (they fail closed on pattern-scan tools), why `guard-secret-reads` hook is the only `fs_read` protection, why `shell: allow` bypasses config guards, and that the `~/.kiro/**` rules bind `fs_write` only. Added engine-enforced `shell: ask` rule on config paths so editing enforcement surface takes a human keystroke. Hot-reload behavior documented.
- **README restructured** — removed all `prompts/` and v2 references. Added model tiering rationale column. Documented the 9 steering files, the naming framework, spec depth levels, skills breakdown (workflow vs capability), true hook coverage with caveats, and the committed test suites.
- **CONTRIBUTING.md** — added naming framework section at the top so new files land in the right category.

### Fixed
- **Three pre-existing guard defects, all now covered by committed test suites**:
  - `guard-secret-reads.sh` — case-folding fixed (filesystem-independent). `~/.SSH/ID_RSA` now blocked. Added `~/.aws/sso/cache/`, `~/.config/gh/`, `~/.git-credentials`, and `*.jks`, `*.ovpn`, `*.kdbx` to patterns.
  - `check-secrets.sh` and `check-dependency-pins.sh` — field-name fixes so hooks fire. Added field-shape fallbacks and `fs_append` matching.
  - `guard-config-writes.sh` — rewritten for target resolution instead of token-position guessing. Now handles redirects, variable indirection, `cd` across segments, interpreter one-liners, and pipelines correctly. 59 test cases document the ordinary spellings that are caught; residual limitations (heredoc-as-code, eval equivalents, unbounded mutator set) are named honestly in the header.

## 2026-06-30

Added **spec depth levels** and consolidated workflow artifacts under `.kiro/`.

### Added
- **Spec depth levels** (`steering/spec-workflow.md`) — a `depth:` frontmatter field (`patch` /
  `prototype` / `standard` / `production`) that scales workflow ceremony. Absent ⇒ `standard`, so the
  default flow is unchanged. Includes a mandatory-gate matrix, a force-upgrade safety floor (security
  review is mandatory whenever a change touches auth/authz/secrets/data/network, regardless of depth),
  and a production-depth structure with `epic.md` / `requirements.md` templates and `phases/` subdirs.
- **`steering/artifact-locations.md`** — `inclusion: always` rule placing workflow state (specs, issues,
  reviews, decisions) under `.kiro/` while keeping deliverables (`README`, `docs/`, `tech.md`, `debt.md`)
  in the repo.
- **Design-review mode** (`agents/reviewer.md`) — the reviewer gains a production-only, pre-construction
  mode that reviews `spec.md` architecture/threat-model/test-strategy and writes `design-review.md`.

### Changed
- **Issues relocated** from the repo root `issues/` to `.kiro/issues/` across `steering/spec-workflow.md`,
  `steering/issue-tracking.md`, and `prompts/diagnose.md`. Migration is forward-only.
- **`prompts/scope.md`** — adds a depth-selection step (default `standard`) that stamps `depth:` into the
  spec and branches the artifacts/gates per rung.
- **`prompts/execute.md`** — reads `depth` and enforces the gate matrix, with the safety floor always on
  and the production design-review gate run before construction.

## 2026-06-22

Migrated the configuration to **Kiro CLI v3**. The previous v2 configuration is archived on the
[`cli-v2`](https://github.com/aws-samples/sample-kiro-cli-multiagent-development/tree/cli-v2) branch.
Run sessions with the v3 engine: `kiro-cli --v3 chat --agent architect`.

### Changed
- **Agents** are now self-contained Markdown profiles (`agents/*.md` — YAML frontmatter + prompt). The
  v2 `.json` configs and embedded hooks were removed. Per-agent `permissions` are intentionally omitted
  (v3 frontmatter requires an object, not the array form the docs show); permissions are governed
  globally by `settings/permissions.yaml`.
- **Hooks** are now standalone `hooks/*.json` manifests with PascalCase triggers, applying to all agents
  in the workspace. Implementation scripts moved to `hooks/scripts/`.
- **`config-drift-guard.sh`** removed — replaced by an `fs_write: ask` rule on the config dir in
  `permissions.yaml`.
- **Per-turn flywheel logging removed** (`flywheel-log.sh`, `flywheel-correction.sh`) — the flywheel now
  parses v3 session transcripts (`~/.kiro/sessions/*/sess_*/messages.jsonl`) directly, so no logging
  hooks are needed.
- **README** rewritten for v3 with a prominent v3 notice and the `cli-v2` archive link.

### Added
- **`settings/permissions.yaml`** — capability-based policy (`deny > ask > allow`): secret read/write
  guards, destructive-shell ask/deny rules, an SSRF `web_fetch` deny, and a `~/.kiro/**` config-dir ask.
- **`hooks/50-rtk-compress.json`** — auto-compresses read-only, RTK-supported command output; mutating,
  metacharacter, and unsupported commands pass through to the normal gated path.
- **`hooks/72-doc-update-check.json`** — an `agent`-action hook (`Manual`) that asks whether
  steering/docs need updating after work.
- **`prompts/flywheel.md`** — rewritten to analyze sessions by parsing v3 transcripts directly.
- **`steering/cli-execution.md`** — RTK token compression + the AWS discover-via-MCP / execute-via-CLI
  workflow.
- **`steering/v3-hooks.md`** — reference for the v3 hook model (triggers, action types, scope).

## 2026-06-15

### Added
- **`steering/minimalism.md`** — a "write the least code that fully works" rule. A six-rung YAGNI escalation ladder (does this need to exist? → stdlib → native platform → installed dependency → one line → minimum that works), "not lazy about" guardrails that never simplify away validation, data-loss handling, security, or accessibility, and the `SHORTCUT:` convention for marking intentional shortcuts with their ceiling and upgrade path. Scoped to product code, not the workflow's own artifacts. (Ladder and guardrails adapted from the ponytail project, MIT.)
- **`prompts/harvest-debt.md`** — collects `SHORTCUT:` markers across the codebase into a `docs/debt.md` ledger, flags markers with no named ceiling, and can hand off to `/scope` for a hardening spec. Read-only on source.
- **`skills/iac-verification/SKILL.md`** — strong render/validate commands for CDK, CloudFormation, Terraform, Docker, and Kubernetes (e.g., `cdk synth`, `aws cloudformation validate-template`, `terraform validate`, `docker build --check`) so IaC tasks are verified by rendering the real output, not by linting or `cat`.
- **`hooks/check-rule-copies.sh`** — maintenance check that keeps the minimalism ladder block in sync across `steering/minimalism.md` and its copies in `coder.md`/`ops.md`. Resolves paths relative to the script; run manually or in CI.

### Changed
- **`steering/spec-workflow.md`** — upgraded the `tasks.md` task contract for delegation to implementer subagents: labeled `Context`/`Files`/`Source`/`Example`/`Accept`/`Verify`/`Constraints` sections, a hard self-containment rule (restate or quote the interfaces a task depends on instead of pointing at "the spec"), a required worked example for repeated patterns, and a per-task "if Verify fails twice, mark `[!]` and stop" rule.
- **`agents/architect.md`** — Task Quality Requirements now reference `spec-workflow.md` as the single source of truth; added a "Writing for implementer subagents" section (be literal, embed the source, give one worked example, state the why, specify verify + stop conditions).
- **`agents/coder.md`** — added a plan-before-code step for multi-file tasks, a "Tool Use & Stop Rules" section (parallel reads, stop on repeated failure, ask before destructive actions), and an inline copy of the minimalism ladder.
- **`agents/ops.md`** — strengthened verification to render/validate rather than lint, added a "Tool Use & Stop Rules" section, and an infra-flavored copy of the minimalism ladder.
- **`agents/reviewer.md`** — added an over-engineering lens (`delete:`/`stdlib:`/`native:`/`yagni:`/`shrink:` tags, Suggestions by default) with a `net: -N lines possible` score, and guidance to write findings as literal, file-scoped, fix-task-ready instructions.
- **`agents/security-reviewer.md`** — remediations must now be literal and file-scoped (exact location and concrete change) so they can be applied without interpretation.
- **`agents/docs.md`** — added a "do not infer behavior you cannot see" guard; document only what is evident in the code, mark `[!]` otherwise.
- **`steering/sdk-verification.md`** — added a rule: never infer an API surface from its name; verify the contract in-session or ask.
- **`steering/testing.md`** — added a minimum-bar floor: non-trivial logic must leave the smallest check that fails if the logic breaks, even when full test-first ceremony isn't warranted.
- **`prompts/execute.md`** — validate that each task is self-contained for an implementer subagent before delegating; tighten under-specified tasks rather than dispatching ambiguity.
- **`prompts/scope.md`** — task planning now applies the `spec-workflow.md` task contract (embedded source, worked example, stop rule).
- **`prompts/flywheel.md`** — pattern recognition now tags each correction by the agent that produced it and adds a "task-authoring" root-cause category, distinguishing an under-specified task from a genuinely wrong rule.
- **`agents/ops.json`** — added the `context7` MCP server so the ops agent can verify provider/CDK APIs against live documentation.

## 2026-05-27

### Added
- **`hooks/flywheel-correction.sh`** — new `userPromptSubmit` hook that filters user prompts for correction signals (explicit corrections, redirects, repeats, quality complaints, tool redirects, terse responses, short questions) and writes them to `~/.kiro/flywheel-corrections.jsonl`. This is now the high-signal starting point for flywheel analysis.
- **`steering/spec-workflow.md`** — added explicit `Group Ordering` and `Mandatory Review Gate` sections that were previously implicit.

### Changed
- **`steering/spec-workflow.md`** — deploys are now out-of-band by default. Most projects deploy via CI/CD pipelines, so the default group ordering is research → implementation → review → documentation. In-spec deploy groups remain available for bootstrap/migration cases. Phase 2 review and security-review steps are tightened as explicit mandatory gates; Phase 3 evaluates both `review.md` and `security-review.md` per cycle.
- **`hooks/flywheel-log.sh`** — rewritten as a lightweight turn index (head+tail preview, smaller cap, smaller per-entry footprint). The new corrections hook now carries the high-signal data, so the turn log only needs to be a positional index.
- **`prompts/flywheel.md`** — reordered to read the corrections log first as the primary source for correction events, with the turn index as supporting context.
- **`agents/architect.json`** — registers the new `flywheel-correction.sh` userPromptSubmit hook.

## 2026-05-11

### Changed
- Renamed `leader` agent to `architect` — better reflects the role (research, design, plan, delegate)
- Updated models: architect uses claude-opus-4-7, ops uses claude-haiku-4-5
- Delegation model now uses `/spawn` for parallel task execution (new TUI feature)
- Added Opus 4.7-specific prompt optimizations: explicit tool-use guidance, stop conditions, scope statements
- **Redesigned review agents** — clear separation of concerns between general reviewer and security reviewer
  - General reviewer: removed security checklist, added spec compliance and regression risk checks
  - Security reviewer: multi-phase methodology (threat model → targeted review → variant hunting → findings report), confidence-scored findings with attack scenarios, moved to claude-opus-4-7

## 2026-04-21

### Added
- **`docs` agent** — dedicated documentation subagent using claude-haiku-4.5 for updating README, architecture docs, and runbooks after spec completion
- **`scope` prompt** — interactive new spec discussion with the leader agent (`/prompts scope`)
- **`execute` prompt** — resume and run the current spec to completion (`/prompts execute`)
- **`diagnose` prompt** — test-first bug fixing from `issues/` reports (`/prompts diagnose`)
- **`steering/issue-tracking.md`** — issue documentation discipline codified as a project steering rule

### Changed
- Updated models: claude-opus-4.5 → claude-opus-4.6, claude-sonnet-4.5 → claude-sonnet-4.6
- `steering/spec-workflow.md` mandatory final documentation group now delegates to the `docs` subagent
- `leader.json` subagent list includes `docs`

## 2026-04-09

### Changed
- Updated coder agent and steering docs

## 2026-02-23

### Added
- Initial release — leader, coder, ops, reviewer, security-reviewer agents
- Steering rules: spec-workflow, SDK verification, doc research, deploy validation, non-interactive execution, virtual environments, documentation, testing, dependency versions
- Skills: agentcore-patterns, aws-cli, cloudwatch-dashboards, docker-build, documentation, git-workflow, shell-scripting
- Hooks: dependency pins, secrets check, config drift guard, destructive command guard, environment validation, git context, flywheel log
- Flywheel prompt for session analysis and config improvement

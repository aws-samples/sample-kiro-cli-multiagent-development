# Changelog

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

# Changelog

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

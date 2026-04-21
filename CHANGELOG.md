# Changelog

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

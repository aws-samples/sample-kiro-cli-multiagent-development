# Workflow Artifact Locations

## Principle

Anything the workflow produces to track its own state — task tracking, issues, reviews, decisions — lives under the project's `.kiro/` directory. Product and engineering deliverables live in the repo where the team and operators expect them.

## The Boundary

| Artifact | Location | Why |
|----------|----------|-----|
| Plans (`plan.md`, `tasks.md`, `epic.md`, `requirements.md`, `phases/`) | `.kiro/delivery/<slug>/` | Workflow state |
| Issues (`report.md`, `summary.md`) | `.kiro/issues/<slug>/` | Workflow state |
| Reviews (`review.md`, `security-review.md`, `design-review.md`) | `.kiro/delivery/<slug>/` | Workflow state |
| Decisions log (`decisions.md`) | `.kiro/delivery/<slug>/` | Workflow state |
| Active-plan pointer (`current.md`) | `.kiro/delivery/` | Workflow state |
| README | repo root | Deliverable |
| Architecture docs | `docs/architecture/` | Deliverable |
| Runbooks | `docs/runbooks/` | Deliverable |
| Verified-API research (`tech.md`) | `docs/tech.md` | Durable engineering reference |
| Tech-debt ledger (`debt.md`) | `docs/debt.md` | Durable operator artifact |
| Source code | repo | Deliverable |

## Rules

1. **Workflow state goes under `.kiro/`** — never at the repo root. The repo root stays clean of process bookkeeping.
2. **Deliverables stay in the repo** — `docs/` and `README.md` are for humans reading the project, not for the agent tracking its work. `docs/tech.md` and `docs/debt.md` are deliberate exceptions to the "research/tracking → .kiro" instinct: they are durable references operators read.
3. **Migration is forward-only.** New artifacts follow this rule immediately. Pre-existing root-level `issues/` directories are migrated manually when convenient — do not auto-migrate repos you are not actively working in.

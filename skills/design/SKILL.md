---
name: design
description: Start a new plan interactively — clarify the problem, research, then write plan.md and tasks.md. Use when asked to design, scope, plan, or start a new plan or feature.
---

# Design New Plan

Start a new plan discussion. Walk through these steps interactively:

## Step 0 — Choose depth

Ask which depth this work is, defaulting to `standard`. Stamp `depth: <rung>` into the created `plan.md` frontmatter. Then branch on the rung:

### `patch` (aliases: bugfix, hotfix, security-patch)

Do **not** create a plan. Redirect immediately to the `.kiro/issues/` flow:

1. Create `.kiro/issues/YYYY-MM-DD-<slug>/report.md` with Summary, Impact, Reproduction, and Investigation sections.
2. Hand off to the `diagnose` skill.
3. **Stop here** — no `plan.md`, no `tasks.md`, no `current.md` entry.

### `prototype` (aliases: poc, spike, throwaway)

Minimal plan only. Covers Steps 1–3 with a reduced artifact:

1. **Understand the problem** — brief clarifying questions about what is being explored.
2. **Research** — targeted codebase/docs check as needed.
3. **Write the plan** — create `.kiro/delivery/YYYY-MM-DD-<slug>/plan.md` with three sections only:
   - `## Context` — why this exists
   - `## Decision` — what is being tried and why alternatives were skipped
   - Flat task list (no groups, no parallel structure)
4. **Security design gate** — if the change touches authentication, authorization, secrets, data handling/migration, or network exposure (the force-upgrade safety floor), stop before writing tasks and run `security-reviewer` in design mode. It reviews the plan for trust boundaries, data flows, and abuse cases, writes findings to `.kiro/delivery/YYYY-MM-DD-<slug>/design-review.md`, and must return PASS before tasks are written or implementation starts.
5. **Set active** — write the slug to `.kiro/delivery/current.md`.

No dedicated review group or documentation group unless the force-upgrade safety floor applies — the security-review gate is then mandatory regardless of depth.

### `standard` (DEFAULT — aliases: feature, refactor, infra)

The full flow:

1. **Understand the problem** — ask clarifying questions about what needs to be built, why, and what constraints exist.
2. **Research** — explore the codebase, check relevant docs, and verify SDK/framework APIs using `aws___search_documentation`, Context7, or `inspect.signature()`. Write verified patterns to `docs/tech.md` before writing any code that calls the SDK.
3. **Write the plan** — create `.kiro/delivery/YYYY-MM-DD-<slug>/plan.md` with:
   - `## Context`
   - `## Decision`
   - `## Constraints`
   - `## Design`
   - `## Risks`
   - `## Threat Model` *(required only when the force-upgrade safety floor triggers — see below)*
4. **Security design gate** — if the change touches authentication, authorization, secrets, data handling/migration, or network exposure (the force-upgrade safety floor), stop before writing tasks and run `security-reviewer` in design mode. It reviews the plan's Threat Model section for trust boundaries, data flows, and abuse cases, writes findings to `.kiro/delivery/YYYY-MM-DD-<slug>/design-review.md`, and must return PASS before tasks are written or implementation starts. Do not proceed past this gate while it is open.
5. **Plan the tasks** — create `tasks.md` with parallelized groups following the delivery-workflow conventions:
   - Group 1: research (mandatory)
   - Implementation groups
   - Review gate (mandatory, sequential — never launch in parallel with other gates)
   - Security-review gate (mandatory after review passes, sequential)
   - Documentation group (mandatory final group)

   Each task requires: **Context**, **Files**, **Accept**, **Verify**, and **Constraints** sections, plus the fail-twice stop rule. Tasks may reference the plan and `docs/tech.md` rather than restating them, but must be completable without knowledge of sibling tasks — that independence is what makes parallel groups safe.
6. **Set active** — write the slug to `.kiro/delivery/current.md`.

### `production` (aliases: full-app, enterprise)

Extended artifact set plus phase sequencing:

1. **Understand the problem** — clarify outcome, stakeholders, milestones, and phase boundaries.
2. **Research** — full codebase and API survey; write findings to `docs/tech.md`.
3. **Write the artifacts** — create in `.kiro/delivery/YYYY-MM-DD-<slug>/`:
   - `epic.md` — outcome, phases (each with a goal and dependency), milestones, cross-phase risks
   - `prd/<feature>.md` — Problem Statement, Goals, Non-Goals, User Stories, Requirements (Must/Should/Won't Have), Success Metrics, Open Questions
   - `requirements.md` — EARS-style functional requirements (`FR-N: The system shall <behavior> when <condition>.`), non-functional requirements, acceptance criteria (`AC-N: Given…, when…, then….`)
   - `plan.md` — Context, Decision, Constraints, Design (with ADRs), Risks, Threat Model, Test Strategy
4. **Product gate** — PRD and requirements must be reviewed and accepted before design proceeds.
5. **Design gate — two parts, sequential** (mandatory at production depth; does not require the safety floor). First `reviewer` in design mode evaluates architecture soundness, feasibility, test strategy, and risks — security explicitly out of scope for it. Then `security-reviewer` in design mode evaluates the Threat Model for trust boundaries, data flows, attack surfaces, and missing bounds. Both write to `design-review.md`, and **a PASS from each** is required before any phase construction starts. Running only the security half skips the architecture review entirely, which is the half that catches an unbuildable or over-complex design before anyone writes code.
6. **Plan the tasks** — per-phase `phases/phase-N-<name>/tasks.md`. Each phase runs the full construction loop: research → implementation → review gate → security-review gate → documentation. Gates are sequential within each phase.
7. **Set active** — write the slug to `.kiro/delivery/current.md`.

---

## Depth quick-reference

| Depth | Aliases | Plan artifact | Security design gate |
|---|---|---|---|
| `patch` | bugfix, hotfix, security-patch | None — routes to `diagnose` | N/A |
| `prototype` | poc, spike, throwaway | Minimal `plan.md` (Context + Decision + flat task list) | When safety floor triggers |
| `standard` *(DEFAULT)* | feature, refactor, infra | Full `plan.md` + `tasks.md` | When safety floor triggers |
| `production` | full-app, enterprise | `epic.md` + `prd/` + `requirements.md` + `plan.md` + `phases/` | Always |

The **force-upgrade safety floor**: if a change touches authentication, authorization, secrets, data handling/migration, or network exposure, the security-review gate is mandatory regardless of declared depth. The design gate uses the same condition — it fires at design time rather than code-review time.

---

## General guidance

Do not rush to implementation. The goal is a well-thought-out plan that a developer can implement from. Ask questions before making assumptions. The gate set scales with the declared depth — see the mandatory-gate matrix in `~/.kiro/steering/delivery-workflow.md`.

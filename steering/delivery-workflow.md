# Plan-Driven Delivery Workflow

> **Not the same thing as `/plan`.** `/plan` (also Shift+Tab) is a built-in Kiro feature that
> *swaps the active agent* for the engine's own `kiro_planner`, and swapping the orchestrator out
> takes its steering, its subagents, and these gates with it. Shift+Tab again returns to the previous
> agent. It writes no files and knows nothing about `.kiro/delivery/`. This workflow's `plan.md` is
> unrelated to it — the collision is in the English word only, and the engine reserves no path here.
>
> **Reserved agent names.** The engine aliases `plan`, `planner`, `quick_plan`, `kiro_planner` to plan
> mode, `spec` and `kiro_spec` to spec mode, and `default` to `vibe`. Never name an agent any of
> those — the mode lookup wins and the agent becomes unreachable.

## When to Create a Plan

Create a plan before any non-trivial work — if it touches multiple files, involves architectural choices, or will be delegated to subagents.

## Plan Depth Levels

A plan's **depth** scales the ceremony up or down to match the work. Depth is declared in `plan.md` YAML frontmatter:

```yaml
---
depth: standard
---
```

**If `depth` is absent, it is `standard`** — the default flow described throughout this document. Other rungs are deltas on `standard`, never separate workflows, so the default cannot drift. Aliases map to a rung (e.g. `bugfix` → `patch`, `poc` → `prototype`, `feature` → `standard`, `enterprise` → `production`).

| Depth | Aliases | Plan artifact | Phasing |
|---|---|---|---|
| `patch` | bugfix, hotfix, security-patch | **None** — routes to the `.kiro/issues/` + `diagnose` flow | depends on complexity |
| `prototype` | poc, spike, throwaway | Minimal `plan.md` (Context + Decision + flat task list) | none |
| `standard` *(DEFAULT)* | feature, refactor, infra | Full `plan.md` + `tasks.md` | parallel groups |
| `production` | full-app, enterprise | `epic.md` + `prd/` + `requirements.md` + `plan.md` + `phases/` | phase subdirs / parallel groups |

**Mandatory-gate matrix** (✓ = required at that depth):

| Gate | patch | prototype | standard | production |
|---|---|---|---|---|
| Research (Group 1) | — | ✓ | ✓ | ✓ (per phase) |
| Runnable check / tests | ✓ | ✓ | ✓ | ✓ |
| Product gate (PRD + requirements) | — | — | — | ✓ |
| Design review | — | — | — | ✓ |
| Security design review | — | floor only | floor only | ✓ |
| Code review | ✓ (via `diagnose`) | optional | ✓ | ✓ (per phase) |
| Security review | ✓ (via `diagnose`) | floor only | ✓ | ✓ (per phase) |
| Documentation | issue `summary.md` | — | ✓ | ✓ |
| Operational readiness | — | — | — | ✓ |

**`patch` is low-*artifact*, not low-*scrutiny*.** It is the one rung that produces no plan, but it is not
a shortcut past the gates: it routes to `.kiro/issues/` and the `diagnose` skill, which mandates a
`report.md` before investigation, a failing test *before* the fix, then the review gate and the
security-review gate sequentially, then a `summary.md` with a Prevention section. Anything describing
`patch` as "no review" or "just make the change and commit" is wrong — a one-line change to an auth check
is still a change to an auth check. If the work genuinely warrants no gate at all, it is a typo, and
`diagnose` explicitly excludes typos, formatting, and trivial one-liners from needing issue docs.

### Force-upgrade safety floor

Regardless of declared depth, if a change touches **authentication, authorization, secrets, data handling/migration, or network exposure**, the security-review gate becomes **mandatory**. Depth can lower ceremony but never below this floor. This is the one rule that overrides the matrix upward — the floor can only ADD a security review, never remove one. **When in doubt about whether a change touches one of these boundaries, run the security review** — erring toward the gate is cheap; skipping a needed one is not.

### Design-review gate

**Reviewer assignment.** The design gate has two parts that run sequentially:

1. **`reviewer` in design mode** — evaluates architecture soundness, feasibility, test strategy, and risks. Security is explicitly out of scope here.
2. **`security-reviewer` in design mode** — evaluates the Threat Model section for trust boundaries, data flows, attack surfaces, and missing bounds. Writes to `design-review.md` (appending a `## Security Design Review — Cycle N` section so code-level reviews are never overwritten).

Both write to `design-review.md`. A PASS from both gates construction. This closes the gap where design is otherwise only validated implicitly at code-review time, after the code already exists.

**When the design gate runs.** Always at `production` depth. At `prototype` and `standard` depth, `security-reviewer`'s design mode runs whenever the plan trips the **force-upgrade safety floor** — that is, when the change touches authentication, authorization, secrets, data handling/migration, or network exposure. This is the same condition that makes the code-level security review mandatory; one condition, two gates. When in doubt, run the gate.

**`standard` plan.md Threat Model section.** When the safety floor triggers at `standard` depth, add a Threat Model section to `plan.md` before the design gate runs — this is the gate's required input. It is not required at `standard` depth when the floor has not triggered.

```markdown
## Threat Model
*(required when the force-upgrade safety floor triggers)*

### Trust boundaries
Where does untrusted data enter the system?

### Data flows
Where does sensitive data travel (storage, transit, logs)? What is the retention and blast radius?

### Attack surfaces
What is exposed to external actors (APIs, ports, endpoints, third-party integrations)?

### Abuse cases
What could an attacker gain, and what are the most plausible exploitation paths?
```

**This gate does not replace the code-level security review.** Both run. A design-time Threat Model is not a license to skim the implementation review.

### Production-depth plan structure

```
.kiro/delivery/<slug>/
  epic.md              # parent: phases, milestones, cross-phase risks, sequencing
  prd/<feature>.md     # required at production depth
  requirements.md      # functional + non-functional requirements, acceptance criteria
  plan.md              # design / ADRs / architecture (+ Threat Model + Test Strategy sections)
  design-review.md     # design gate findings
  phases/
    phase-1-<name>/tasks.md
    phase-2-<name>/tasks.md
  review.md            # per phase
  security-review.md   # per phase
  decisions.md
```

**`epic.md` template:**

```markdown
# Epic: <Title>

## Outcome
The production-level outcome this epic delivers.

## Phases
1. **Phase 1 — <name>**: <goal> — depends on: none
2. **Phase 2 — <name>**: <goal> — depends on: Phase 1
...

## Milestones
- <milestone> — exit criteria

## Cross-phase risks
- <risk> — mitigation
```

**`requirements.md` template:**

```markdown
# Requirements: <Title>

## Functional (EARS-style)
- FR-1: The system shall <behavior> when <condition>.
- FR-2: ...

## Non-functional
- NFR-1: <performance / availability / security / compliance target>

## Acceptance criteria
- AC-1 (FR-1): Given <context>, when <action>, then <observable outcome>.
```

The product gate (PRD + requirements signed off) precedes the design gate, which precedes per-phase construction, which precedes the operational-readiness gate (observability + runbook + deploy & rollback validated). Each phase under `phases/` runs the full standard construction loop (research → impl → code review → security review → docs).

## Directory Structure

```
.kiro/delivery/current.md  # Tracks current plan slug in use
.kiro/delivery/YYYY-MM-DD-<slug>/
  plan.md        # Design decisions, requirements, constraints
  tasks.md       # Parallelized task list for execution
  review.md      # Reviewer findings per cycle
  security-review.md  # Security reviewer findings per cycle
  decisions.md   # Mid-flight decision log
  prd/           # Product requirements documents (when work involves product roadmap decisions)
    <descriptive-title>.md

.kiro/issues/YYYY-MM-DD-<slug>/
  report.md      # Problem description, reproduction steps, impact, investigation
  summary.md     # Root cause, fix applied, prevention, status
```

Use a date-prefixed kebab-case slug for plan and issue folders. The date is the creation date in `YYYY-MM-DD` format, followed by a short descriptive slug (e.g., `2026-03-04-auth-api`, `2026-02-27-vpc-redesign`). This ensures chronological ordering when listing directories.

## Active Plan Tracking (`current.md`)

`current.md` contains a single line: the slug of the active plan. This is the source of truth for which plan is in progress.

```markdown
2026-03-04-auth-api
```

**Rules:**
- **Write** when creating a new plan (Phase 1, step 2) — set to the new slug
- **Read** at the start of any workflow phase to resolve the active plan path (`delivery/<slug>/`)
- **Clear** (delete the file) when the plan is complete (all groups pass review)
- Only one plan is active at a time. Starting a new plan overwrites the previous slug.

## Plan Format (`plan.md`)

```markdown
# <Title>

## Context
Why this work exists. Link to issues, conversations, or prior decisions.

## Decision
What we're doing and why. Include alternatives considered and why they were rejected.

## Constraints
- Budget, timeline, team, technical limitations
- Non-functional requirements (performance, security, compliance)

## Design
Technical approach — interfaces, data models, flows, diagrams as needed.

## Risks
Known unknowns and mitigation strategies.
```

## Task Format (`tasks.md`)

Tasks are organized into parallel groups. All tasks within a group can be executed simultaneously by independent subagents. Groups execute sequentially — group 2 starts only after group 1 is complete.

```markdown
# Tasks: <Title>

Plan: `delivery/<slug>/plan.md`

## Group 1: <description>
- [ ] Task description | `path/to/relevant/files`
  - **Context**: why this task exists — state the intent so the implementer understands the tradeoff space
  - **Files**: exact paths to read and to create/modify
  - **Packages**: exact package names and versions when dependencies are involved (e.g., `strands-agents==0.1.x`)
  - **Source**: non-obvious interfaces, signatures, or constants the task depends on — quote only what is hard to locate, point at `docs/tech.md` or the plan for the rest
  - **Example** (for genuinely ambiguous shapes): one concrete input→output showing the expected form; if existing code shows the same pattern, point at it instead
  - **Accept**: measurable completion criteria
  - **Verify**: command(s) the subagent must run before marking complete
  - **Goal** *(optional — see Goal-loop tasks below)*: a single command whose success is a sufficient definition of done, phrased for `/goal`
  - **Constraints**: explicit "do not" rules, known naming gotchas, scope boundaries, and the stop rule — "if Verify fails twice for the same reason, mark `[!]` with the error and stop; do not keep editing"

## Group 2: <description>
- [ ] Task description | `path/to/relevant/files`
  - **Context**: why this task exists
  - **Files**: exact paths to read and to create/modify
  - **Accept**: measurable completion criteria
  - **Verify**: command(s) the subagent must run before marking complete
  - **Constraints**: stop rule and any "do not" rules
```

### Goal-loop tasks (optional `Goal` field)

`/goal` starts an agent loop that cycles through implementation and **self-check** until it judges the
acceptance criteria met (default 5 iterations, `--max` configurable). It is user-invoked, so a task
cannot start one itself — the `Goal` field exists so a task is *written* such that a human can point
`/goal` at it and walk away.

**A task earns a `Goal` line only when its stop condition is a command exit code, never a judgment.**

| Qualifies | Does not qualify |
|---|---|
| `pytest tests/test_auth.py` passes | "authentication is implemented correctly" |
| `bash hooks/scripts/test-guard.sh` reports all cases correct | "the guard is secure" |
| `npx tsc --noEmit` exits clean | "the types are well designed" |
| `cdk synth MyStack` succeeds | "the infrastructure is sound" |

The reason is specific and load-bearing: `/goal`'s quality gate is the *same agent* assessing its own
work. Self-assessment validates what the implementation already believes. A command written before the
implementation — or by someone other than the implementer — does not.

Format:

```markdown
- [ ] Harden the config-write guard | `hooks/scripts/guard-config-writes.sh`
  - **Verify**: `bash hooks/scripts/test-guard-config-writes.sh`
  - **Goal**: `bash hooks/scripts/test-guard-config-writes.sh` reports all cases correct
    — safe under `/goal --max 3`
```

Rules:

- Set `--max` deliberately rather than accepting the default. A loop that stops mid-task is worse than
  one that never started, because the task will read as attempted.
- Never wrap a **review gate** or **security-review gate** in `/goal` — see the gate templates below.
- Never wrap a whole plan or task group. `/goal`'s loop and the `execute` loop have different stop
  conditions, and nesting them means neither is in charge: the outer loop can halt mid-group or iterate
  past a FAIL verdict that the 3-cycle safeguard requires escalating to the user.
- A `Goal` line is an addition to `Verify`, never a replacement. Verification discipline does not relax
  because a loop is doing the work.

### Task Rules

Implementation tasks are executed by `coder` and `ops`, which run on **Claude Sonnet 4.6**. That model reads the plan, follows references, infers surrounding intent, and self-verifies. Write tasks that give it the *problem* and let it choose the *solution*:

- **State the intent, not the keystrokes.** A one-line **Context** explaining why the task exists produces better tradeoffs than a paragraph prescribing how. Do not spell out an implementation the implementer can derive.
- **Reference, don't transcribe.** Point at the plan section, the `docs/tech.md` entry, or the file to read. Restate inline only what is genuinely hard to locate — an exact constant, a non-obvious signature, a schema that lives outside the repo. Wholesale restatement of the plan inflates the task and degrades output on a model this strong.
- **Give an example only for a genuinely ambiguous shape.** If the expected output form is inferable from existing code, point at the existing code instead.
- **Keep Accept, Verify, and the stop rule mandatory on every task.** State measurable completion criteria, at least one command that actually validates the output (not merely that a file parses), and "if Verify fails twice for the same reason, mark `[!]` with the error and stop." Verification discipline does not relax with implementer strength — it is what makes delegation trustworthy.
- **Name the constraints that are not inferable.** Explicit "do not" rules, known naming gotchas, and scope boundaries still need stating; the implementer cannot guess a policy it has not been told.
- Each task specifies exact file paths (**Files**) and clear acceptance criteria
- For any task that involves dependencies, include **Packages** with exact PyPI/npm names and version constraints
- Subagents mark tasks `[x]` when complete — only after verification passes
- If a task is blocked or fails, mark it `[!]` and add a note below it
- Keep tasks small enough that one subagent can finish in a single session

### Group Ordering

The default task group ordering is:

1. Research group (mandatory Group 1)
2. Implementation groups (one or more)
3. **Review gate** — all implementation groups must pass review before proceeding
4. Documentation group (mandatory final group)

**Deploys are out-of-band by default.** Most projects deploy via a CI/CD pipeline that runs after the plan is merged — the pipeline is not part of the plan's task list, and the plan finishes at the documentation group.

**In-plan deploy groups are the exception, not the rule.** Only include a deploy group when the plan itself must perform a deploy to be considered done — e.g., bootstrapping new infrastructure before a pipeline exists, or one-off migrations that don't fit the pipeline. A deploy group is any group whose tasks include `deploy.sh`, `cdk deploy`, infrastructure provisioning, or production-affecting operations.

When a plan does include an in-plan deploy group, the ordering is:

1. Research group
2. Implementation groups
3. **Review gate** — must issue PASS before deploy runs
4. Deploy/verification group
5. Documentation group (still the final group)

Documentation is always the final group regardless of whether a deploy group is present.

### Verification Requirements by Technology

**Verify** commands must actually validate the output, not just check that files parse or import:

| Technology | Weak (don't use) | Strong (use this) |
|-----------|-------------------|-------------------|
| CDK | `python3 -c "from stack import MyStack"` | `cdk synth StackName 2>&1` |
| CloudFormation | `cat template.yaml` | `aws cloudformation validate-template --template-body file://template.yaml` |
| Terraform | `terraform fmt` | `terraform validate` |
| Docker | `cat Dockerfile` | `docker build --check .` |
| Python | `python3 -c "import module"` | `python3 -m pytest tests/ -v` |
| TypeScript | `cat src/index.ts` | `npx tsc --noEmit` |

Import checks only prove a file parses — they do NOT validate that constructs, resources, or configurations are correct. Always use the tool's own validation command.

### Dependency Research

Every plan that introduces or relies on SDK/framework APIs MUST include a research step before implementation tasks.

**Group 1 must include a documentation research task** that:
1. Looks up current API docs for each key dependency (AWS docs, Context7, official docs)
2. Verifies constructor signatures, handler conventions, and import paths
3. Writes findings to the project's `docs/tech.md`
4. Implementation tasks in later groups reference `docs/tech.md` — not assumed APIs

**Mandatory Group 1 task template:**

```markdown
- [ ] Research and document SDK/framework APIs | `docs/tech.md`
  - **Accept**: `docs/tech.md` contains verified import paths, constructor signatures, and usage patterns for all key dependencies in this plan
  - **Verify**: Each documented pattern has a source citation (doc URL or `inspect.signature()` output)
  - **Constraints**: Implementation tasks MUST reference `docs/tech.md` — do not write code against unverified APIs
```

**Additional requirements for alpha/preview packages:**
- Pin exact versions in the plan (no ranges)
- Run `inspect.signature()` or equivalent to verify actual API surface
- Flag in plan Constraints section which deps are alpha vs stable

### Mandatory Review Gate

Every plan MUST include a review gate after all implementation groups complete. The orchestrator delegates to the `reviewer` subagent to inspect all implementation work.

- **Default (no in-plan deploy group):** the review gate is the second-to-last group, immediately before documentation.
- **Plan includes an in-plan deploy group (rare — see Group Ordering):** the review gate runs before deploy (research → implementation → review gate → deploy → documentation).

**Mandatory review gate task template:**

```markdown
## Group N: Review gate
- [ ] Code review of all implementation groups | `.kiro/delivery/<slug>/review.md`
  - **Accept**: Reviewer has written findings to `review.md` with verdict PASS. Zero critical findings, zero warnings.
  - **Verify**: `bash .kiro/tools/check-review-verdict.sh .kiro/delivery/<slug>/review.md` (exit 0 only if the LATEST verdict is PASS; a stale earlier PASS or an unfilled `PASS | FAIL` placeholder does not open the gate)
  - **Constraints**: Do NOT proceed to the next group until this passes. Three cycles per gate, per group — when a 3rd cycle FAILs the check exits 3, which means stop and escalate to the user, not open a cycle 4. A 4th cycle is a workflow violation; decreasing severity and findings confined to your own test scaffolding are not exceptions. **Never wrap this gate in `/goal`** — its value comes from a fresh-context agent that did not write the code, and a self-verifying loop would be grading its own homework. No `Goal` field on gate tasks, ever.
```

**Mandatory security-review gate task template:**

```markdown
## Group N+1: Security review gate
- [ ] Security review of all implementation groups | `.kiro/delivery/<slug>/security-review.md`
  - **Accept**: `security-reviewer` has written findings to `security-review.md` with verdict PASS. Zero critical findings, zero warnings.
  - **Verify**: `bash .kiro/tools/check-review-verdict.sh .kiro/delivery/<slug>/security-review.md` (same semantics as the review gate)
  - **Constraints**: Runs ONLY after the general review returns PASS — these are sequential gates, never parallel. Three cycles, then stop and escalate; exit 3 from the check means the budget is spent, not that another cycle is due. Never wrap in `/goal`.
```

**Why checking the verdict is sufficient for the `Accept` criteria.** `Accept` demands zero criticals and
zero warnings, and `Verify` only inspects the verdict — those agree because the verdict is *defined* by
that condition: a review verdict is FAIL if any Critical or Warning exists. So a PASS verdict already
asserts zero of both. If you loosen the verdict rule, this gate silently loosens with it.

**Why not `grep`.** The obvious check, `grep -i 'verdict.*pass' review.md`, cannot fail. `review.md` is
append-only per cycle, so a cycle-1 PASS keeps matching after cycle 2 returns FAIL; and the unfilled
template line `### Verdict: PASS | FAIL` matches too, so an untouched template opens the gate. Both were
reproduced. `check-review-verdict.sh` reads only the *last* filled-in verdict, rejects placeholders that
offer both outcomes, and exits non-zero when no verdict exists — "no verdict" must never read as approval.
Its behaviour is pinned by `tools/test-check-review-verdict.sh` (26 cases).

The same prohibition applies to the security-review gate. A verdict is a judgment, not a command exit
code, so it can never be a `/goal` stop condition — see *Goal-loop tasks* above.

**Exit codes.** `0` PASS · `1` FAIL, fix and run the next cycle · `2` no usable verdict (missing file,
unfilled placeholder, or a cycle with findings but no verdict recorded) · `3` **cycle budget spent —
stop and escalate.** Treating 3 as "another FAIL" and opening one more cycle is the specific violation
the code exists to prevent; see *Loop Safeguards*.

### Mandatory Final Group: Documentation Update

The last group in every `tasks.md` MUST include a documentation update task. Documentation written against finished, reviewed code is accurate documentation. Delegate this task to the `docs` subagent.

**Mandatory final group task template:**

```markdown
## Group N: Documentation update
- [ ] Update documentation for plan changes | `README.md`, `docs/`
  - **Accept**: README and relevant docs reflect all changes made in this plan — no stale references, no missing features
  - **Verify**: `grep -r 'TODO\|FIXME\|PLACEHOLDER' README.md docs/ || true` returns no plan-related placeholders
  - **Constraints**: Do not document features that were descoped or marked `[!]` in earlier groups
```

What to update (check each):
- **README.md** — if user-facing behavior, CLI commands, config, dependencies, or folder structure changed
- **Architecture docs** — if services, data flows, or integration patterns changed
- **Inline docstrings** — if public function/class signatures changed
- **Runbooks** — if operational procedures or deployment steps changed

### Parallelization Guidelines

When structuring groups, maximize parallelism:
- **Test skeletons go in early groups** — define expected behavior before implementation
- Implementation tasks reference the tests they must make pass
- Tasks with no shared file writes go in the same group
- Tasks that produce outputs consumed by later tasks go in earlier groups
- Infrastructure before application code
- Shared libraries/interfaces before consumers
- Tests can often parallel with implementation if interfaces are defined first

## Review Format (`review.md`)

The reviewer writes findings here. Each review cycle gets its own section.

```markdown
# Review: <Title>

## Cycle 1 — <date>
Reviewing: Group 1 tasks

### Critical
- [file:line] Description of issue and recommended fix

### Warning
- [file:line] Description of issue and recommended fix

### Suggestion
- [file:line] Description of improvement

### Tests
- [ ] All tests passing
- [ ] Test coverage adequate for changes

### Verdict: PASS | FAIL
```

Verdict is **FAIL** if any Critical or Warning findings exist, or tests are not passing. Otherwise **PASS**.

## Security Review Format (`security-review.md`)

The security reviewer writes findings here. The security review happens after the general review passes. Each cycle gets its own section.

```markdown
# Security Review: <Title>

## Cycle 1 — <date>
Reviewing: Groups 1-N

### Critical
- [file:line] Description of vulnerability and remediation

### Warning
- [file:line] Description of risk and recommended mitigation

### Suggestion
- [file:line] Description of hardening opportunity

### Verdict: PASS | FAIL
```

Verdict is **FAIL** if any Critical or Warning security findings exist. Otherwise **PASS**.

## Decisions Log (`decisions.md`)

Records decisions made during implementation that aren't significant enough for the plan but need to be tracked. Prevents the same question from being re-asked across cycles.

```markdown
# Decisions: <Title>

## <date> — <short description>
**Context**: What prompted the decision
**Decision**: What was decided
**Rationale**: Why
```

## Product Requirements Document (`prd.md`)

Create a PRD when the work involves a product roadmap decision — new features, feature changes, deprecations, or anything that affects what the product does for users. Not needed for purely technical/infrastructure work with no user-facing impact.

- **Location**: `prd/<descriptive-title>.md` within the plan folder
- **File naming**: Use a descriptive kebab-case title (e.g., `prd/user-auth-sso-support.md`)

```markdown
# PRD: <Title>

## Problem Statement
What user problem or opportunity this addresses.

## Goals
- Measurable outcomes this work should achieve

## Non-Goals
- What this work explicitly does NOT cover

## User Stories
- As a [persona], I want [action] so that [outcome]

## Requirements
### Must Have
- [requirement]

### Should Have
- [requirement]

### Won't Have (this iteration)
- [requirement]

## Success Metrics
How we measure whether this achieved its goals.

## Open Questions
Unresolved product decisions that need stakeholder input.
```

## Issues (`.kiro/issues/`)

Issues track bugs, problems, and investigations. They live under `.kiro/issues/YYYY-MM-DD-<slug>/`.

**Any bug fix that changes code gets a `report.md` and a `summary.md`** — no silent fixes, and every
`summary.md` needs a Prevention section. The `diagnose` skill lists the narrow exclusions (typos,
formatting, trivial one-liners) along with the full criteria, templates, and the review/security-review
gate sequence; this rule is stated here so it applies even when that skill has not been activated.

### Issue Report (`report.md`)

```markdown
# Issue: <Title>

## Summary
One-line description of the problem.

## Impact
Who/what is affected and severity.

## Reproduction
Steps to reproduce, environment details, relevant logs.

## Investigation
What was checked, what was ruled out, root cause analysis.
```

### Issue Summary (`summary.md`)

Written after the issue is resolved.

```markdown
# Resolution: <Title>

## Root Cause
What caused the issue.

## Fix Applied
What was changed and where.

## Prevention
What prevents recurrence (tests, monitoring, guardrails).

## Status
RESOLVED | MITIGATED | WONT_FIX
```

## Development Loop

### Phase 1: Plan
1. **Research** — gather context, explore codebase, check docs
2. **SDK/Framework research** — for each dependency, look up current API docs using AWS documentation search and Context7. Write verified patterns, import paths, and constructor signatures to the project's `docs/tech.md`
3. **Plan document** — write `plan.md` with decisions and design (reference `docs/tech.md` for API contracts), then write the slug to `.kiro/delivery/current.md`. At `production` depth or when the safety floor triggers, include a Threat Model section.
4. **Security design review (when required)** — if at `production` depth, or if the plan trips the force-upgrade safety floor, delegate to `security-reviewer` (and `reviewer` at `production` depth) in design mode before creating tasks. Both write to `design-review.md`. A PASS gates step 5 — verify with `bash .kiro/tools/check-review-verdict.sh .kiro/delivery/<slug>/design-review.md`, which is the same check the two construction gates use.
5. **Task breakdown** — create `tasks.md` with parallelized groups

### Phase 2: Build (per group)
1. **Read `.kiro/delivery/current.md`** to resolve the active plan slug and path
2. **Delegate via `/spawn`** — use `/spawn` to launch group tasks to `coder` and/or `ops` agents in parallel. Each spawned agent runs independently with its own context.
3. **Verify completion** — confirm all tasks in the group are `[x]`
4. **Run tests** — execute the test suite, confirm all tests pass
5. **Review (mandatory gate)** — delegate to `reviewer`, who writes findings to `review.md`. Do NOT proceed to the next group until the review verdict is PASS. This step is not optional — skipping review is a workflow violation.
6. **Security review (mandatory gate)** — after the general review passes, delegate to `security-reviewer`, who writes findings to `security-review.md`. Do NOT proceed until both reviews pass.

> ⚠️ **ANTI-PATTERN — DO NOT PARALLELIZE REVIEW GATES**
>
> Review (step 5), security review (step 6), and documentation are SEQUENTIAL gates, not parallel tasks.
> The correct order is: review → wait for PASS → security review → wait for PASS → next group.
> NEVER launch review, security-review, and documentation subagents simultaneously.
> This is the most common workflow violation. Speed does not justify skipping gates.

### Phase 3: Fix (if needed)
1. **Read `.kiro/delivery/current.md`** to resolve the active plan
2. **Evaluate reviews** — read `review.md` and `security-review.md` for the current cycle
3. **If FAIL** — create fix tasks as a new group in `tasks.md` (e.g., `## Fix Group 1: Address review cycle 1`), then go to step 1 of Phase 2
4. **If PASS** — proceed to next group (back to Phase 2 step 1) or finish
5. **On completion** (all groups pass) — delete `.kiro/delivery/current.md`

### Completion Criteria

The loop stops when ALL of the following are true:
- **Zero critical findings** in the latest review cycle
- **Zero warnings** in the latest review cycle
- **Zero critical findings** in the latest security review cycle
- **Zero warnings** in the latest security review cycle
- **All tests passing**
- **All tasks marked `[x]`**

Suggestions do NOT block completion — log them for future improvement.

### Loop Safeguards
- **Three review cycles per gate, per group. A 4th is a workflow violation, not a judgment call.**
  When a 3rd cycle records FAIL, the budget is spent: stop, and hand the user a summary of the
  unresolved findings. `check-review-verdict.sh` exits **3** at that point rather than 1, so the
  boundary arrives as a distinct signal instead of another "keep fixing".
- These are **not** exceptions, and each has been used verbatim by an agent to justify a 4th cycle:
  - "severity is decreasing across cycles"
  - "the remaining findings are only in test scaffolding I added, not the core change"
  - "one more cycle purely to verify, then I'll stop"
  - "I'm past the limit but I'll be upfront with the user about it" — **disclosure is not
    authorisation.** Announcing an overrun does not convert it into an approved one.
- A cycle that arrives at PASS after the budget was blown does not settle the gate. By cycle 4 a
  loop is often adjusting its own tests toward green, which converts a FAIL into a PASS without
  fixing anything. The check latches for this reason: only the user reopens a spent gate, by
  recording a `Budget override:` line in the review file.
- Escalating at 3 is the *successful* outcome of the safeguard. Three failed cycles means the loop
  is not converging, and a human deciding what to do next is cheaper than a 5th cycle.
- Log each decision made during fixes in `decisions.md` to prevent re-litigation.

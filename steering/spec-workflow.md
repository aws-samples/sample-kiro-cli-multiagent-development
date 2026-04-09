---
inclusion: always
---

# Spec-Driven Workflow

## When to Create a Spec

Create a spec before any non-trivial work — if it touches multiple files, involves architectural choices, or will be delegated to subagents.

## Directory Structure

```
.kiro/specs/currentspec.md  # Tracks current spec slug in use
.kiro/specs/YYYY-MM-DD-<slug>/
  spec.md        # Design decisions, requirements, constraints
  tasks.md       # Parallelized task list for execution
  review.md      # Reviewer findings per cycle
  security-review.md  # Security reviewer findings per cycle
  decisions.md   # Mid-flight decision log
  prd/           # Product requirements documents (when work involves product roadmap decisions)
    <descriptive-title>.md

issues/YYYY-MM-DD-<slug>/
  report.md      # Problem description, reproduction steps, impact, investigation
  summary.md     # Root cause, fix applied, prevention, status
```

Use a date-prefixed kebab-case slug for spec and issue folders. The date is the creation date in `YYYY-MM-DD` format, followed by a short descriptive slug (e.g., `2026-03-04-auth-api`, `2026-02-27-vpc-redesign`). This ensures chronological ordering when listing directories.

## Current Spec Tracking (`currentspec.md`)

`currentspec.md` contains a single line: the slug of the active spec. This is the source of truth for which spec is in progress.

```markdown
2026-03-04-auth-api
```

**Rules:**
- **Write** when creating a new spec (Phase 1, step 2) — set to the new slug
- **Read** at the start of any workflow phase to resolve the active spec path (`specs/<slug>/`)
- **Clear** (delete the file) when the spec is complete (all groups pass review)
- Only one spec is active at a time. Starting a new spec overwrites the previous slug.

## Spec Format (`spec.md`)

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

Spec: `specs/<slug>/spec.md`

## Group 1: <description>
- [ ] Task description | `path/to/relevant/files`
  - **Packages**: exact package names and versions (e.g., `strands-agents==0.1.x`, not `strands`)
  - **Accept**: measurable completion criteria
  - **Verify**: command(s) the subagent must run before marking complete
  - **Constraints**: explicit "do not" rules or known gotchas

## Group 2: <description>
- [ ] Task description | `path/to/relevant/files`
  - **Accept**: measurable completion criteria
  - **Verify**: command(s) the subagent must run before marking complete
```

### Task Rules

- Each task MUST be self-contained — a subagent should be able to complete it with no knowledge of sibling tasks in the same group
- Each task specifies relevant file paths and clear acceptance criteria
- Every task MUST include an **Accept** field with measurable criteria and a **Verify** field with at least one command to run
- Include **Packages** with exact PyPI/npm names and version constraints when the task involves dependencies
- Include **Constraints** to call out known naming gotchas, common mistakes, or explicit "do not" rules
- Subagents mark tasks `[x]` when complete — only after verification passes
- If a task is blocked or fails, mark it `[!]` and add a note below it
- Keep tasks small enough that one subagent can finish in a single session

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

Every spec that introduces or relies on SDK/framework APIs MUST include a research step before implementation tasks.

**Group 1 must include a documentation research task** that:
1. Looks up current API docs for each key dependency (AWS docs, Context7, official docs)
2. Verifies constructor signatures, handler conventions, and import paths
3. Writes findings to the project's `docs/tech.md`
4. Implementation tasks in later groups reference `docs/tech.md` — not assumed APIs

**Mandatory Group 1 task template:**

```markdown
- [ ] Research and document SDK/framework APIs | `docs/tech.md`
  - **Accept**: `docs/tech.md` contains verified import paths, constructor signatures, and usage patterns for all key dependencies in this spec
  - **Verify**: Each documented pattern has a source citation (doc URL or `inspect.signature()` output)
  - **Constraints**: Implementation tasks MUST reference `docs/tech.md` — do not write code against unverified APIs
```

**Additional requirements for alpha/preview packages:**
- Pin exact versions in the spec (no ranges)
- Run `inspect.signature()` or equivalent to verify actual API surface
- Flag in spec Constraints section which deps are alpha vs stable

### Mandatory Final Group: Documentation Update

The last group in every `tasks.md` MUST include a documentation update task. Documentation written against finished, reviewed code is accurate documentation.

**Mandatory final group task template:**

```markdown
## Group N: Documentation update
- [ ] Update documentation for spec changes | `README.md`, `docs/`
  - **Accept**: README and relevant docs reflect all changes made in this spec — no stale references, no missing features
  - **Verify**: `grep -r 'TODO\|FIXME\|PLACEHOLDER' README.md docs/ || true` returns no spec-related placeholders
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

Records decisions made during implementation that aren't significant enough for the spec but need to be tracked. Prevents the same question from being re-asked across cycles.

```markdown
# Decisions: <Title>

## <date> — <short description>
**Context**: What prompted the decision
**Decision**: What was decided
**Rationale**: Why
```

## Product Requirements Document (`prd.md`)

Create a PRD when the work involves a product roadmap decision — new features, feature changes, deprecations, or anything that affects what the product does for users. Not needed for purely technical/infrastructure work with no user-facing impact.

- **Location**: `prd/<descriptive-title>.md` within the spec folder
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

## Issues (`issues/`)

Issues track bugs, problems, and investigations. They live at the project root in `issues/YYYY-MM-DD-<slug>/`.

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
3. **Spec** — write `spec.md` with decisions and design (reference `docs/tech.md` for API contracts), then write the slug to `.kiro/specs/currentspec.md`
4. **Plan** — create `tasks.md` with parallelized groups

### Phase 2: Build (per group)
1. **Read `.kiro/specs/currentspec.md`** to resolve the active spec slug and path
2. **Delegate** — send group tasks to `coder` and/or `ops` subagents in parallel
3. **Verify completion** — confirm all tasks in the group are `[x]`
4. **Run tests** — execute the test suite, confirm all tests pass
5. **Review** — delegate to `reviewer`, who writes findings to `review.md`
6. **Security review** — after the general review passes, delegate to `security-reviewer`, who writes findings to `security-review.md`. Do NOT proceed until both reviews pass.

> ⚠️ **ANTI-PATTERN — DO NOT PARALLELIZE REVIEW GATES**
>
> Review (step 5), security review (step 6), and documentation are SEQUENTIAL gates, not parallel tasks.
> The correct order is: review → wait for PASS → security review → wait for PASS → next group.
> NEVER launch review, security-review, and documentation subagents simultaneously.
> This is the most common workflow violation. Speed does not justify skipping gates.

### Phase 3: Fix (if needed)
1. **Read `.kiro/specs/currentspec.md`** to resolve the active spec
2. **Evaluate review** — read `review.md` for the current cycle
3. **If FAIL** — create fix tasks as a new group in `tasks.md` (e.g., `## Fix Group 1: Address review cycle 1`), then go to step 1 of Phase 2
4. **If PASS** — proceed to next group (back to Phase 2 step 1) or finish
5. **On completion** (all groups pass) — delete `.kiro/specs/currentspec.md`

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
- Maximum 3 review cycles per group. If still failing after 3, escalate to the user with a summary of unresolved criticals.
- Log each decision made during fixes in `decisions.md` to prevent re-litigation.

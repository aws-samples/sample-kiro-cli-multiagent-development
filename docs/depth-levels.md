# Plan Depth Levels

Not every change deserves the same ceremony. Depth levels let you match workflow rigor to the risk of what you're building.

## Depth Table

| Depth | When to Use | What Happens |
|-------|-------------|--------------|
| `patch` | Bug fixes, hotfixes, security patches — anything where the goal is to correct broken behavior | No spec document. Routes to `.kiro/issues/` and the `diagnose` skill: issue `report.md`, a failing test written *before* the fix, the fix, then the review gate and the security-review gate in sequence, then a `summary.md` with a Prevention section. **Low artifact, not low scrutiny** — a one-line change to an auth check is still a change to an auth check. Genuine typos and formatting are excluded from needing issue docs. |
| `prototype` | Experiments, spikes, throwaway exploration, learning exercises | Minimal `plan.md` (Context + Decision + a flat task list, no groups). Research still required. Code review is **optional**, not a single mandatory pass. Security review only if the safety floor applies. No documentation group. The runnable-check floor still applies — see [testing](../steering/testing.md). |
| `standard` | Most feature work, bug fixes, refactors with moderate scope | Full plan with task list. Parallel implementation via `/spawn`. General review + security review gates. Fix loops until both pass. Documentation group at the end. |
| `production` | Customer-facing features, data migrations, auth changes, infrastructure with blast radius | Everything in `standard`, plus a larger artifact set and two extra gates. Artifacts: `epic.md`, `prd/<feature>.md`, `requirements.md` (EARS-style + acceptance criteria), `plan.md` with Threat Model and Test Strategy sections, and per-phase `phases/phase-N-*/tasks.md`. Gates, in order: **product gate** (PRD + requirements signed off) → **design gate** (both `reviewer` *and* `security-reviewer` in design mode, sequentially, both writing `design-review.md`) → per-phase construction, each phase running the full standard loop → **operational-readiness gate** (observability, runbook, deploy and rollback validated). |

## Safety Floor

Regardless of declared depth, if a change touches **authentication, authorization, secrets, data
handling/migration, or network exposure**, the security-review gate becomes mandatory. Depth can lower
ceremony but never below this floor, and the floor can only ever *add* a security review — never remove
one.

Note all five boundaries: **authorization** is distinct from authentication, and a pure permissions change
trips the floor on its own.

**This is a rule the agent applies, not a feature the system enforces.** There is no detector, hook, or
engine check that reads your plan and elevates the gate — the orchestrator is instructed to apply the
floor, and `steering/delivery-workflow.md` tells it that when in doubt it should run the gate, because erring
toward the gate is cheap and skipping a needed one is not. If you are choosing depth by hand, you own
that judgment too.

## Choosing a Depth

When in doubt, start with `standard`. Drop to `prototype` for experiments. Elevate to `production` for anything customer-facing or data-migrating.

The `/design` workflow asks you to pick a depth at the start of plan creation. You can override it later by editing the `depth:` field in the plan frontmatter before running `/execute`.


## Goal-Loop Tasks

Kiro's `/goal` command starts an agent loop that cycles through implementation and **self-check** until it
judges the acceptance criteria met (default 5 iterations, `--max` configurable). A task in `tasks.md` may
carry an optional `Goal` field so you can point `/goal` at that one task and walk away:

```markdown
- [ ] Harden the config-write guard | `hooks/scripts/guard-config-writes.sh`
  - **Verify**: `bash hooks/scripts/test-guard-config-writes.sh`
  - **Goal**: `bash hooks/scripts/test-guard-config-writes.sh` reports all cases correct
    — safe under `/goal --max 3`
```

`/goal` is user-invoked, so a task cannot start one itself. The field exists so the task is *written* such
that a human can.

### The stop condition must be a command, never a judgment

| Qualifies | Does not qualify |
|---|---|
| `pytest tests/test_auth.py` passes | "authentication is implemented correctly" |
| `bash hooks/scripts/test-guard.sh` reports all cases correct | "the guard is secure" |
| `npx tsc --noEmit` exits clean | "the types are well designed" |
| `cdk synth MyStack` succeeds | "the infrastructure is sound" |

The reason is specific. `/goal`'s quality gate is the *same agent* assessing its own work, and
self-assessment validates what the implementation already believes. This configuration has direct evidence: the guard test
suites now shipped under `hooks/scripts/test-*.sh` were each written by the same author as the guard they
test, and each reported green while an independently written attack matrix was still finding bypasses in
the same guard. The suites were green at the moment they were most wrong. That is why the review and
security-review gates are held by agents that did not write the code.

### Where not to use it

- **Never on the review or security-review gates.** A verdict is a judgment, and the gates' entire value is
  a fresh-context agent that did not write the code. Wrapping one in a self-verifying loop is grading your
  own homework.
- **Never around a whole plan or task group.** `/goal`'s loop and the `execute` skill's loop have different
  stop conditions, so nesting them means neither is in charge: the outer loop can halt mid-group, or
  iterate past a FAIL verdict that the 3-cycle safeguard requires escalating to a human.
- Set `--max` deliberately rather than taking the default. A loop that stops mid-task is worse than one
  that never started, because the task reads as attempted.

### Best fit: the diagnose flow

`diagnose` writes a failing test *before* the fix, at a different step than the one being verified. That
makes it the one place in this workflow where the acceptance criterion does not inherit the
implementation's assumptions:

```
/goal --max 3 make `pytest tests/test_<module>.py::<test_name>` pass without breaking the rest of the suite
```

Phrase the goal as the command, not the outcome. Do not extend it through the review gates.

A `Goal` line is an addition to `Verify`, never a replacement — verification discipline does not relax
because a loop is doing the work.

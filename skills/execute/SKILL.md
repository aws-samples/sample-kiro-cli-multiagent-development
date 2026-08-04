---
name: execute
description: Execute the active plan's task groups in order, delegating to coder/ops/reviewer/docs subagents. Use when asked to execute, run, or build out the current plan or its tasks.
---

# Execute Current Plan

Read `.kiro/delivery/current.md` to resolve the active plan slug.
Read the plan at `.kiro/delivery/<slug>/plan.md` and the task list at `.kiro/delivery/<slug>/tasks.md`.

**Read the plan's depth first.** Take `depth` from the `plan.md` YAML frontmatter; if absent, it is `standard`. Depth determines which gates are mandatory — see the mandatory-gate matrix in `## Plan Depth Levels` of `~/.kiro/steering/delivery-workflow.md`. Enforce gates per that matrix:
- `prototype` — research + a runnable check; skip the code-review and documentation gates. The safety floor can still force a security review.
- `standard` *(default)* — the full sequence below, unchanged: research → impl → code review → security review → docs.
- `production` — run the **design-review gate before construction** (two parts, sequential: `reviewer` in design mode reviews `plan.md` architecture/feasibility/test-strategy/risks, then `security-reviewer` in design mode reviews the Threat Model; both write to `design-review.md`; PASS from both required), then run the standard construction loop **per phase** across `phases/phase-N-*/tasks.md`, and finish with the operational-readiness gate.

**Force-upgrade safety floor (always on).** If a change touches authentication, authorization, secrets, data handling/migration, or network exposure, you MUST run the security-review gate even when the declared depth would skip it. The floor can only ADD a security review, never remove one. When in doubt about whether a change crosses one of these boundaries, run the security review.

**The floor also arms the security design gate.** At `prototype` and `standard` depth, when the floor is tripped, run `security-reviewer` in design mode *before* construction begins — it reviews the plan's Threat Model section and writes to `design-review.md`, and a PASS gates the start of implementation. Same condition, two gates: one at design time, one at code-review time. The design gate never substitutes for the code-level security review.

Execute all incomplete task groups in order. For each group:

1. **Classify each task by owner** before executing:
   - Research / API verification → execute yourself (the orchestrator) using your tools
   - Implementation → delegate to `coder` subagent
   - Infrastructure / deploy → delegate to `ops` subagent
   - Review gate → delegate to `reviewer` subagent (then `security-reviewer`)
   - Documentation → delegate to `docs` subagent
2. Execute your tasks first — subagent tasks may depend on research output (e.g., `docs/tech.md`)
3. Before delegating, validate each task carries what the contract in `~/.kiro/steering/delivery-workflow.md` → *Task Rules* requires: **Context** stating intent, **Files**, **Accept** with measurable criteria, a **Verify** command that validates the output rather than merely proving a file parses, **Constraints** including the fail-twice stop rule, and an **Example** only where the expected shape is genuinely ambiguous. Tasks may reference the plan and `docs/tech.md` rather than restating them, but must be completable without knowledge of sibling tasks. If a task is under-specified, tighten it in `tasks.md` *before* spawning — do not dispatch ambiguity downstream.
4. Use `/spawn` to delegate implementation tasks in parallel (where no dependencies exist)
5. Verify all tasks are marked `[x]` before proceeding to the next group
6. Run review and security review gates sequentially — do not skip or parallelize them (subject to the depth matrix and the always-on safety floor)
7. If review fails, create fix tasks and re-run

Continue until all groups required at this depth are complete and all required reviews pass.

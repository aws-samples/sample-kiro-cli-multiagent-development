# Execute Current Spec

Read `.kiro/specs/currentspec.md` to resolve the active spec slug.
Read the spec at `.kiro/specs/<slug>/spec.md` and the task list at `.kiro/specs/<slug>/tasks.md`.

Execute all incomplete task groups in order. For each group:
1. Delegate tasks to the appropriate subagents in parallel
2. Verify all tasks are marked `[x]` before proceeding
3. Run the review gate — do not skip reviews
4. If review fails, create fix tasks and re-run

Continue until all groups are complete and all reviews pass.

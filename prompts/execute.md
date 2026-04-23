# Execute Current Spec

Read `.kiro/specs/currentspec.md` to resolve the active spec slug.
Read the spec at `.kiro/specs/<slug>/spec.md` and the task list at `.kiro/specs/<slug>/tasks.md`.

Execute all incomplete task groups in order. For each group:

1. **Classify each task by owner** before executing:
   - Research / API verification → execute yourself (Leader) using your tools
   - Implementation → delegate to `coder` subagent
   - Infrastructure / deploy → delegate to `ops` subagent
   - Review gate → delegate to `reviewer` subagent (then `security-reviewer`)
   - Documentation → delegate to `docs` subagent
2. Execute your tasks first — subagent tasks may depend on research output (e.g., `docs/tech.md`)
3. Delegate implementation tasks to subagents (parallel where no dependencies exist)
4. Verify all tasks are marked `[x]` before proceeding to the next group
5. Run review and security review gates sequentially — do not skip or parallelize them
6. If review fails, create fix tasks and re-run

Continue until all groups are complete and all reviews pass.

# Execute Current Spec

Read `.kiro/specs/currentspec.md` to resolve the active spec slug.
Read the spec at `.kiro/specs/<slug>/spec.md` and the task list at `.kiro/specs/<slug>/tasks.md`.

Execute all incomplete task groups in order. For each group:

1. **Classify each task by owner** before executing:
   - Research / API verification → execute yourself (Architect) using your tools
   - Implementation → delegate to `coder` subagent
   - Infrastructure / deploy → delegate to `ops` subagent
   - Review gate → delegate to `reviewer` subagent (then `security-reviewer`)
   - Documentation → delegate to `docs` subagent
2. Execute your tasks first — subagent tasks may depend on research output (e.g., `docs/tech.md`)
3. Before delegating, validate each task is self-contained for an implementer subagent: it embeds or quotes the interfaces/signatures it needs, has a concrete **Verify** command, a worked **Example** if it implements a repeated pattern, and a stop rule. If a task is under-specified, tighten it in `tasks.md` *before* spawning — do not dispatch ambiguity downstream.
4. Use `/spawn` to delegate implementation tasks in parallel (where no dependencies exist)
5. Verify all tasks are marked `[x]` before proceeding to the next group
6. Run review and security review gates sequentially — do not skip or parallelize them
7. If review fails, create fix tasks and re-run

Continue until all groups are complete and all reviews pass.

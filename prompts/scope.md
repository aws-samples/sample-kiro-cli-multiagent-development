# Scope New Spec

Start a new spec discussion. Walk through these steps interactively:

1. **Understand the problem** — ask clarifying questions about what needs to be built, why, and what constraints exist
2. **Research** — explore the codebase, check relevant docs, and verify SDK/framework APIs as needed
3. **Write the spec** — create `.kiro/specs/YYYY-MM-DD-<slug>/spec.md` with Context, Decision, Constraints, Design, and Risks
4. **Plan the tasks** — create `tasks.md` with parallelized groups following the spec-workflow conventions (research group first, review gates, documentation last). Apply the task contract from `.kiro/steering/spec-workflow.md`: each task gets labeled `Context`/`Files`/`Source`/`Accept`/`Verify`/`Constraints` sections, embeds or quotes the interfaces it depends on, includes a worked **Example** for any repeated pattern, and carries the fail-twice stop rule. Tasks must be completable by an implementer subagent with no spec or sibling-task context.
5. **Set active** — write the slug to `.kiro/specs/currentspec.md`

Do not rush to implementation. The goal is a well-thought-out spec that a developer can implement from. Ask questions before making assumptions.

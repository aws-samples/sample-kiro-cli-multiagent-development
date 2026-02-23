---
inclusion: always
---

# Documentation Requirements

## Principle

Every non-trivial change must include documentation. Code without docs is unfinished work.

## What Must Be Documented

### Always (every spec)
- **README updates** — if the change adds, removes, or modifies user-facing behavior, CLI commands, configuration, or dependencies
- **Inline code docs** — public functions/classes get docstrings explaining purpose, parameters, return values, and exceptions/errors

### When Applicable
- **Architecture docs** — for new services, significant redesigns, or new integration patterns. Place in `docs/architecture/` or alongside the spec
- **Runbooks** — for new operational procedures, deployment steps, or incident response changes. Place in `docs/runbooks/`
- **API docs** — for new or changed API endpoints. Include request/response examples
- **Configuration docs** — for new environment variables, feature flags, or config files

## Task Planning Rules

When creating `tasks.md`, the leader MUST:
1. Include a mandatory documentation update task as the **final group** — see `spec-workflow.md` for the required template
2. README updates go in the same group as the feature they document (for mid-spec updates) or in the final documentation group
3. Architecture docs go in the first group (written alongside or before implementation)
4. Runbooks go in the final group (after implementation is stable)
5. For non-spec work (simple changes), the leader must still check for and perform documentation updates as part of the task

## Documentation Standards

- Docs live next to the code they describe (prefer `docs/` in project root)
- Use Markdown
- Keep it concise and actionable — no filler paragraphs
- Include working examples, not just descriptions
- Update existing docs — don't leave stale docs behind

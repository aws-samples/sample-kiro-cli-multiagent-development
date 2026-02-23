---
inclusion: always
---

# SDK & Framework Verification

## Principle

Verify API contracts from authoritative sources before writing code. Never rely on model knowledge alone — SDKs change between versions, and hallucinated APIs are the #1 source of preventable errors in generated code.

## Tiers

### Tier 1: Always Verify (every project)
- Constructor/factory signatures for primary SDK classes being used
- IAM resource ARN formats (these vary by service and resource type)
- Framework handler/entrypoint conventions (parameter names, return types)
- Import paths (package restructuring between versions is common)

### Tier 2: Deep Verify (alpha, preview, or unfamiliar SDKs)
- All Tier 1 checks, plus:
- Full API surface inspection via `inspect.signature()` or equivalent
- Cross-reference multiple sources (official docs, source code, changelogs)
- Pin exact versions — no ranges for alpha/preview packages

## Research Sources (in priority order)

1. **Project steering docs** — check `docs/tech.md` or project `.kiro/steering/` first
2. **AWS documentation** — use `aws___search_documentation` for AWS services
3. **Context7** — use `resolvelibraryid` + `querydocs` for framework/library docs
4. **Official changelogs/migration guides** — for version-specific changes
5. **Source code inspection** — `inspect.signature()`, reading library source

## Rules

1. **Verify before writing** — look up actual API signatures before writing any code that calls the SDK
2. **Document what you find** — write verified patterns to the project's `docs/tech.md` so they aren't re-researched by future tasks
3. **Check project docs first** — the project's `docs/tech.md` may already have verified patterns; use those before searching externally
4. **Version-lock discoveries** — note which version the verification applies to; patterns may change on upgrade

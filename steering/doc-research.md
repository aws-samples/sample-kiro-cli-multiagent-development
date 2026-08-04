# Documentation Research & SDK Verification

## Principle

Always consult authoritative, up-to-date documentation before writing implementation code. Verify API contracts from authoritative sources before writing any code that calls the SDK. Model training data goes stale and hallucinated APIs are the #1 source of preventable errors in generated code — live documentation does not lie.

## When to Research

- **Starting a new plan** — look up APIs for every key dependency
- **Adding a dependency** — verify import paths, constructor signatures, usage patterns
- **Debugging an error** — search for the error message in official docs before guessing
- **Writing IAM policies** — verify ARN formats and required actions per service
- **Writing infrastructure code** — verify resource properties and valid values

## Never Infer an API From Its Name

**Do not assume a constructor signature, method name, parameter order, or import path because it resembles a convention from another library or "looks right."** A plausible-sounding name is not verification. If you have not confirmed the API surface in this session (via docs, `inspect.signature()`, or source), look it up or ask.

Name-based guessing is the most common source of preventable errors and is especially likely to slip through when the implementer is confident.

## Verification Tiers

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

## How to Research

### Research Sources (in priority order)

1. **Project steering docs** — check `docs/tech.md` or project `.kiro/steering/` first
2. **AWS documentation** — use `aws___search_documentation` for AWS services
3. **Context7** — use `resolvelibraryid` + `querydocs` for framework/library docs
4. **Official changelogs/migration guides** — for version-specific changes
5. **Source code inspection** — `inspect.signature()`, reading library source

### AWS Services
Use `aws___search_documentation` with specific service + feature queries.
Use `aws___read_documentation` to read specific pages in full.

Examples:
- "S3 bucket encryption configuration" → reference_documentation
- "Lambda function URL CORS" → reference_documentation
- "Bedrock InvokeModel IAM permissions" → reference_documentation
- "ECS service connect" → general

### Frameworks & Libraries
Use `resolvelibraryid` to find the Context7 library ID, then `querydocs` to search the library's documentation.

Examples:
- resolvelibraryid("aws-cdk-lib") → querydocs("/aws/aws-cdk", "S3 bucket encryption")
- resolvelibraryid("strands-agents") → querydocs("/strands-agents/sdk-python", "agent tools")

### CDK Constructs
Use `search_cdk_documentation` for CDK API references and patterns.
Use `search_cdk_samples_and_constructs` for working code examples.

## Rules

1. **Verify before writing** — look up actual API signatures before writing any code that calls the SDK
2. **Check project docs first** — `docs/tech.md` may already have verified patterns; use those before searching externally
3. **Document what you find** — write verified patterns to the project's `docs/tech.md` so they aren't re-researched by future tasks
4. **Version-lock discoveries** — note which version the verification applies to; patterns may change on upgrade

## Output: `docs/tech.md`

Write research findings to the project's `docs/tech.md` with:
- Package name and version verified against
- Import paths
- Constructor/function signatures with parameter types
- Verified usage patterns with working code snippets
- Source URL for each finding
- Date of verification

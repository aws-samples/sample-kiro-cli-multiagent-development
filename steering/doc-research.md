---
inclusion: always
---

# Documentation Research

## Principle

Always consult authoritative, up-to-date documentation before writing implementation code. Model training data goes stale — live documentation does not.

## When to Research

- **Starting a new spec** — look up APIs for every key dependency
- **Adding a dependency** — verify import paths, constructor signatures, usage patterns
- **Debugging an error** — search for the error message in official docs before guessing
- **Writing IAM policies** — verify ARN formats and required actions per service
- **Writing infrastructure code** — verify resource properties and valid values

## How to Research

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

## Output

Write research findings to the project's `docs/tech.md` with:
- Package name and version verified against
- Import paths
- Constructor/function signatures with parameter types
- Verified usage patterns with working code snippets
- Source URL for each finding
- Date of verification

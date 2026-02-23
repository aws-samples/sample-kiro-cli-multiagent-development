---
name: documentation
description: Technical documentation patterns including READMEs, API docs, runbooks, and architecture decision records. Use when writing documentation, creating runbooks, or documenting system architecture.
---

# Documentation

## README Structure

```markdown
# Project Name

One-line description of what this does.

## Quick Start

\`\`\`bash
npm install
npm start
\`\`\`

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| PORT | Server port | 3000 |

## Usage

[Examples of common operations]

## Development

[How to set up dev environment, run tests]

## License

MIT
```

## API Documentation

Use OpenAPI/Swagger. Minimum per endpoint:
- HTTP method and path
- Request parameters (path, query, body)
- Response codes and schemas
- Authentication requirements
- Example request/response

## Runbook Template

```markdown
# [Service Name] Runbook

## Overview
What this service does, who owns it.

## Architecture
[Diagram or description of components]

## Health Checks
- Endpoint: `GET /health`
- Expected: 200 OK

## Common Issues

### Issue: High latency
**Symptoms**: Response times > 500ms
**Diagnosis**: Check DB connections, cache hit rate
**Resolution**: Scale horizontally, clear cache

## Escalation
- L1: On-call engineer
- L2: Service owner
- L3: Platform team
```

## Architecture Decision Record (ADR)

```markdown
# ADR-001: Use PostgreSQL for user data

## Status
Accepted

## Context
Need persistent storage for user accounts.

## Decision
Use PostgreSQL on RDS.

## Consequences
- Pro: ACID compliance, familiar tooling
- Con: Operational overhead vs DynamoDB
```

## Writing Tips

- Lead with the "what" and "why"
- Use concrete examples over abstract explanations
- Keep it scannable (headers, bullets, tables)
- Update docs when code changes (or automate it)

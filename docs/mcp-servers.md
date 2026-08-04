# MCP Server Configuration

This configuration uses the following MCP servers:

| Server | Source | Used By |
|--------|--------|---------|
| [aws-knowledge-mcp-server](https://knowledge-mcp.global.api.aws) | AWS (official) | All except `docs` (which declares `mcpServers: {}`) |
| [awslabs.document-loader-mcp-server](https://github.com/awslabs/mcp) | AWS Labs (official) | architect |
| [awslabs.aws-iac-mcp-server](https://github.com/awslabs/mcp) | AWS Labs (official) | architect, coder, ops |
| [context7](https://github.com/upstash/context7) | Upstash (open source) | architect, coder, ops, reviewer, security-reviewer |
| [deepwiki](https://mcp.deepwiki.com) | DeepWiki (public) | architect |

## What They Provide

Context7 provides live documentation lookup for any library or framework. DeepWiki provides AI-powered Q&A against GitHub repositories. Together with the AWS documentation servers, these give agents access to current API references instead of relying on training data.

The architect uses these servers to verify SDK/framework APIs before implementation begins. Findings go into a `docs/tech.md` in your own project — created at runtime by the research task, not a file shipped in this repo — so subagents code against verified contracts, not assumed APIs.

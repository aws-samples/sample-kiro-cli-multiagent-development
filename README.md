# Kiro CLI Multi-Agent Development Sample

A sample configuration for multi-agent development workflows using [Kiro CLI](https://kiro.dev). Demonstrates how to set up a team of specialized AI agents that collaborate through a spec-driven development process.

This entire setup — agents, steering rules, skills, and prompts — was built using Kiro CLI itself.

> **Disclaimer**: This repository is provided as an example only. The agent configurations, steering rules, and workflows are starting points — not production-ready defaults. You should review, adjust, and tailor them to fit your own project requirements, team conventions, and security posture.

## Overview

This repo provides a sample `.kiro` configuration with four agents that work together:

| Agent | Role | Model |
|-------|------|-------|
| **leader** | Architect — researches, designs specs, creates plans, delegates work | claude-opus-4.5 |
| **coder** | Implements features and writes tests from specs | claude-sonnet-4.5 |
| **ops** | Infrastructure, CI/CD, containers, and documentation | claude-sonnet-4.5 |
| **reviewer** | Reviews implementations for correctness, security, and quality | claude-opus-4.5 |

The `leader` agent orchestrates the workflow: it writes specs, breaks work into parallelized task groups, delegates to `coder` and `ops` for implementation, then sends the results to `reviewer` for feedback. This loop continues until the reviewer passes the work.

## How It Works

```
leader (plan + research) → coder + ops (build in parallel) → reviewer (verify) → leader (next group or fix)
```

1. **Plan** — `leader` researches the problem, looks up SDK/framework APIs from live documentation, writes a spec, and creates a task plan
2. **Build** — `leader` delegates task groups to `coder` and/or `ops` subagents in parallel
3. **Review** — `reviewer` analyzes the implementation and writes findings
4. **Fix** — if the review fails, `leader` creates fix tasks and loops back to build

Before any implementation begins, the leader conducts SDK/framework research using AWS documentation and Context7 to verify API signatures, import paths, and constructor conventions. Findings are written to the project's `docs/tech.md` so subagents code against verified contracts — not assumed APIs.

## Quick Start

1. Install [Kiro CLI](https://kiro.dev)

2. Copy the configuration files to your Kiro config directory:

```bash
# Copy agents, steering, skills, and settings to ~/.kiro/
cp -r agents/ ~/.kiro/agents/
cp -r steering/ ~/.kiro/steering/
cp -r skills/ ~/.kiro/skills/
cp -r settings/ ~/.kiro/settings/
```

3. Update the `prompt` paths in each agent JSON file to point to your `~/.kiro/` directory:

```bash
# Example: in ~/.kiro/agents/leader.json, change:
#   "prompt": "file://agents/leader.md"
# to:
#   "prompt": "file:///Users/<you>/.kiro/agents/leader.md"
```

4. Start a chat with the leader agent:

```bash
kiro-cli chat --agent leader
```

## Repository Structure

```
├── agents/                  # Agent definitions (JSON config + markdown prompts)
│   ├── leader.json          # Leader agent config (MCP servers, tools, subagent access)
│   ├── leader.md            # Leader agent system prompt
│   ├── coder.json / .md     # Coder agent config and prompt
│   ├── ops.json / .md       # Ops agent config and prompt
│   └── reviewer.json / .md  # Reviewer agent config and prompt
├── steering/                # Global behavioral rules for all agents
│   ├── spec-workflow.md     # Spec-driven development loop with dependency research
│   ├── sdk-verification.md  # Universal SDK/framework API verification tiers
│   ├── doc-research.md      # Mandatory documentation research before implementation
│   ├── deploy-validation.md # Post-deploy smoke test requirements
│   ├── non-interactive.md   # All commands must run non-interactively
│   ├── virtual-environments.md  # Dependency isolation requirements
│   ├── documentation.md     # Documentation requirements for every spec
│   ├── testing.md           # Test-first development workflow
│   └── latest-versions.md   # Use latest stable versions by default
├── skills/                  # Domain-specific knowledge files
│   ├── agentcore-patterns/  # Amazon Bedrock AgentCore runtime, gateway, and memory patterns
│   ├── aws-cli/             # AWS CLI best practices
│   ├── cloudwatch-dashboards/ # CloudWatch dashboard observability patterns
│   ├── docker-build/        # Docker image building patterns
│   ├── documentation/       # Technical writing patterns
│   ├── git-workflow/        # Git operations and conventions
│   └── shell-scripting/     # Bash/Zsh scripting patterns
└── settings/
    └── cli.json             # Kiro CLI settings (default agent, model)
```

## Key Concepts

**Agents** define who does what. Each agent has a JSON config (tools, MCP servers, model) and a markdown prompt (role, constraints, workflow).

**Steering** files are global rules that apply to all agents. They enforce consistency — like requiring non-interactive execution, dependency isolation, or mandatory SDK verification before writing code.

**Skills** are domain-specific knowledge that agents can reference. They provide patterns and best practices for specific tools and technologies.

**Specs** are created at runtime in `.kiro/specs/YYYY-MM-DD-<slug>/` and contain the design decisions, task plans, review findings, and decision logs for each piece of work. Date-prefixed slugs ensure chronological ordering.

**Issues** are tracked in `issues/YYYY-MM-DD-<slug>/` at the project root. Each issue has a `report.md` (problem description, reproduction, investigation) and a `summary.md` (root cause, fix, prevention) written after resolution.

## Steering Rules

| Rule | Purpose |
|------|---------|
| `spec-workflow.md` | Defines the full plan → build → review loop with parallel task groups, mandatory dependency research, mandatory final documentation group, and issue tracking |
| `sdk-verification.md` | Tiered API verification — Tier 1 (always verify signatures, ARNs, imports) and Tier 2 (deep verify for alpha/unfamiliar SDKs) |
| `doc-research.md` | Mandates using AWS documentation search and Context7 to look up live docs before writing implementation code |
| `deploy-validation.md` | Every deploy script must include a post-deploy smoke test; exit non-zero on failure |
| `non-interactive.md` | All commands must run without user prompts — pass flags, provide all inputs via arguments |
| `virtual-environments.md` | Project dependency isolation per language (venv, node_modules, cargo, go mod) |
| `documentation.md` | Every non-trivial change must include documentation updates; mandatory final group in every spec |
| `testing.md` | Test-first development — define tests before or alongside implementation |
| `latest-versions.md` | Use latest stable/LTS versions unless project config specifies otherwise |

## Agent JSON Configuration

Each agent JSON file supports these fields:

| Field | Purpose |
|-------|---------|
| `name` | Agent identifier |
| `description` | Human-readable role description |
| `prompt` | Path to the markdown system prompt |
| `mcpServers` | MCP server configurations (HTTP or stdio) |
| `tools` | Tool access pattern (`"*"` for all) |
| `toolAliases` | Custom tool name mappings |
| `allowedTools` | Explicit tool allowlist |
| `resources` | File and skill resource patterns |
| `hooks` | Lifecycle hooks (pre/post actions) |
| `toolsSettings` | Tool-specific config (e.g., subagent access) |
| `useLegacyMcpJson` | Whether to use legacy MCP config format |
| `model` | AI model to use |

## Subagent Limitations

When agents run as subagents (delegated by the leader), some tools are not available in the subagent runtime:

| Available | Not Available |
|-----------|---------------|
| `read`, `write`, `shell` | `web_search`, `web_fetch` |
| `code` (symbol search, references) | `use_aws` (AWS CLI) |
| MCP tools | `grep`, `glob` |
| | `thinking` |

Subagents can still execute AWS CLI commands via the `shell` tool, but won't have the structured `use_aws` tool. Plan your agent prompts accordingly.

## MCP Servers

This configuration uses the following MCP servers:

| Server | Source | Used By |
|--------|--------|---------|
| [aws-knowledge-mcp-server](https://knowledge-mcp.global.api.aws) | AWS (official) | All agents |
| [awslabs.document-loader-mcp-server](https://github.com/awslabs/mcp) | AWS Labs (official) | leader |
| [awslabs.aws-iac-mcp-server](https://github.com/awslabs/mcp) | AWS Labs (official) | leader, coder, ops |
| [context7](https://github.com/upstash/context7) | Upstash (open source) | leader, coder, reviewer |
| [deepwiki](https://mcp.deepwiki.com) | DeepWiki (public) | leader |

Context7 provides live documentation lookup for any library or framework. DeepWiki provides AI-powered Q&A against GitHub repositories. Together with the AWS documentation servers, these give agents access to current API references instead of relying on training data.

## Experimental Features (Optional)

This configuration ships with GA (generally available) features only. To enhance the experience, you can opt into these experimental features:

```bash
# Thinking tool — shows AI reasoning for complex problems
kiro-cli settings chat.enableThinking true

# Knowledge management — persistent context storage with semantic search
kiro-cli settings chat.enableKnowledge true

# Checkpointing — git-like snapshots of file changes during a session
kiro-cli settings chat.enableCheckpoint true

# Tangent mode — conversation checkpoints to explore side topics
kiro-cli settings chat.enableTangentMode true

# Context usage indicator — shows context window usage percentage in prompt
kiro-cli settings chat.enableContextUsageIndicator true
```

These features may change or be removed. See [Experimental Features](https://kiro.dev/docs/cli/experimental/) for details.

## Customization

- **Add agents**: Create a new `<name>.json` and `<name>.md` in `agents/`, then add the agent name to `leader.json`'s `toolsSettings.subagent.availableAgents` array
- **Add steering rules**: Drop a markdown file in `steering/` — all agents will follow it
- **Add skills**: Create a `<name>/SKILL.md` in `skills/` — agents reference these for domain knowledge
- **Change models**: Edit the `model` field in each agent's JSON config. Available GA models: `auto`, `claude-opus-4.5`, `claude-sonnet-4.5`, `claude-sonnet-4.0`, `claude-haiku-4.5`
- **Change default agent**: Edit `chat.defaultAgent` in `settings/cli.json`

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.

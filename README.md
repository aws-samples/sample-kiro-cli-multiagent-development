# Kiro CLI Multi-Agent Development Sample

A sample configuration for multi-agent development workflows using [Kiro CLI](https://kiro.dev). Demonstrates how to set up a team of specialized AI agents that collaborate through a spec-driven development process.

This entire setup — agents, steering rules, skills, and prompts — was built using Kiro CLI itself.

> **Disclaimer**: This repository is provided as an example only. The agent configurations, steering rules, and workflows are starting points — not production-ready defaults. You should review, adjust, and tailor them to fit your own project requirements, team conventions, and security posture.

## Overview

This repo provides a sample `.kiro` configuration with five agents that work together:

| Agent | Role | Model |
|-------|------|-------|
| **leader** | Architect — researches, designs specs, creates plans, delegates work | claude-opus-4.5 |
| **coder** | Implements features and writes tests from specs | claude-sonnet-4.5 |
| **ops** | Infrastructure, CI/CD, containers, and documentation | claude-sonnet-4.5 |
| **reviewer** | Reviews implementations for correctness, quality, and maintainability | claude-opus-4.5 |
| **security-reviewer** | Reviews implementations exclusively for security vulnerabilities and misconfigurations | claude-opus-4.5 |

The `leader` agent orchestrates the workflow: it writes specs, breaks work into parallelized task groups, delegates to `coder` and `ops` for implementation, then sends the results to `reviewer` and `security-reviewer` for feedback. This loop continues until both reviewers pass the work.

## How It Works

```
leader (plan + research) → coder + ops (build in parallel) → reviewer (verify) → security-reviewer (security audit) → leader (next group or fix)
```

1. **Plan** — `leader` researches the problem, looks up SDK/framework APIs from live documentation, writes a spec, and creates a task plan
2. **Build** — `leader` delegates task groups to `coder` and/or `ops` subagents in parallel
3. **Review** — `reviewer` analyzes the implementation for correctness and quality
4. **Security Review** — after the general review passes, `security-reviewer` audits for vulnerabilities, misconfigurations, and compliance risks
5. **Fix** — if either review fails, `leader` creates fix tasks and loops back to build

Before any implementation begins, the leader conducts SDK/framework research using AWS documentation and Context7 to verify API signatures, import paths, and constructor conventions. Findings are written to the project's `docs/tech.md` so subagents code against verified contracts — not assumed APIs.

## Quick Start

1. Install [Kiro CLI](https://kiro.dev)

2. Clone this repo into a project's `.kiro/` directory (or use it standalone):

```bash
git clone https://github.com/aws-samples/sample-kiro-cli-multiagent-development.git .kiro
cd .kiro
chmod +x hooks/*.sh
```

3. Start a chat with the leader agent:

```bash
kiro-cli chat --agent leader
```

Everything works immediately — agent prompts, steering rules, skills, and hooks all use relative paths.

## Moving to Global Configuration

If you want these agents available across all your projects (not just this directory), promote the local config to `~/.kiro/`:

```bash
# Copy everything to global config
cp -r agents/ steering/ skills/ hooks/ prompts/ settings/ ~/.kiro/
chmod +x ~/.kiro/hooks/*.sh

# Update agent prompt paths from relative to absolute
# In each ~/.kiro/agents/*.json, change:
#   "prompt": "file://agents/leader.md"
# to:
#   "prompt": "file:///Users/<you>/.kiro/agents/leader.md"

# Update hook paths from local to global
# In each ~/.kiro/agents/*.json, change:
#   "command": ".kiro/hooks/check-secrets.sh"
# to:
#   "command": "~/.kiro/hooks/check-secrets.sh"
```

Local `.kiro/` takes precedence over global `~/.kiro/` — remove the local copy after promoting to avoid conflicts.

## Repository Structure

```
├── agents/                  # Agent definitions (JSON config + markdown prompts)
│   ├── leader.json          # Leader agent config (MCP servers, tools, subagent access)
│   ├── leader.md            # Leader agent system prompt
│   ├── coder.json / .md     # Coder agent config and prompt
│   ├── ops.json / .md       # Ops agent config and prompt
│   ├── reviewer.json / .md  # Reviewer agent config and prompt
│   └── security-reviewer.json / .md  # Security reviewer config and prompt
├── hooks/                   # Hook scripts — executed at agent lifecycle trigger points
│   ├── check-dependency-pins.sh  # Block unpinned versions in dependency files
│   ├── check-secrets.sh          # Block writes containing secrets or API keys
│   ├── config-drift-guard.sh     # Block writes to config without approval
│   ├── flywheel-log.sh           # Log turn summaries for flywheel analysis
│   ├── git-context.sh            # Inject git status into agent context
│   ├── guard-destructive-commands.sh  # Block dangerous shell commands
│   └── validate-environment.sh   # Check required tools on agent spawn
├── prompts/                 # Stored prompts — reusable workflows invoked by name
│   └── flywheel.md          # Session analysis → config improvement loop
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

**Prompts** are stored workflows that you invoke by name. Unlike agent prompts (which define an agent's role), stored prompts are reusable task definitions — like scripts for the agent. See [The Flywheel](#the-flywheel) below for an example.

**Hooks** are scripts that execute at agent lifecycle trigger points — before/after tool use, on agent spawn, on user prompt submit, and when the assistant finishes responding. They enable enforcement (blocking unsafe operations), logging (collecting data for the flywheel), and guardrails (preventing config drift). See [Hooks](#hooks) below.

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
| `latest-versions.md` | Pin dependency versions, 7-day quarantine on new releases, security patch exception |

## Hooks

Hooks are shell scripts that fire at specific points during agent execution. They receive JSON context via stdin and control behavior through exit codes: `0` to allow, `2` to block (preToolUse only), anything else to warn.

### Enforcement hooks (preToolUse — block before damage)

| Hook | Matcher | Purpose |
|------|---------|---------|
| `check-dependency-pins.sh` | `fs_write` | Blocks writes to `package.json`, `requirements.txt`, `pyproject.toml`, or `Cargo.toml` with unpinned versions. Protects against supply chain attacks. |
| `check-secrets.sh` | `fs_write` | Blocks writes containing AWS keys, private keys, GitHub/Slack tokens, or generic API key patterns. Allowlists `.md` files and placeholder values. |
| `config-drift-guard.sh` | `fs_write` | Blocks writes to steering/skills/agents config directories. Prevents agents from silently modifying their own configuration. Bypass with `KIRO_ALLOW_CONFIG_WRITES=1`. |
| `guard-destructive-commands.sh` | `execute_bash` | Blocks `rm -rf /`, `DROP TABLE`, `terraform destroy` (without `-target`), `git push --force` to protected branches, and `kubectl delete namespace` on critical namespaces. |

### Context hooks (agentSpawn / userPromptSubmit — inject information)

| Hook | Trigger | Purpose |
|------|---------|---------|
| `validate-environment.sh` | `agentSpawn` | Checks that required tools are installed (python3, git, node, aws, docker, cargo) and prints versions. Exits non-zero only if critical tools are missing. |
| `git-context.sh` | `userPromptSubmit` | Injects a one-line git summary (branch, staged/modified/untracked counts, last commit) into agent context. Silent no-op outside git repos. |

### Observability hooks (stop — log after the fact)

| Hook | Trigger | Purpose |
|------|---------|---------|
| `flywheel-log.sh` | `stop` | Logs turn summaries to `~/.kiro/flywheel-log.jsonl` for the [flywheel prompt](#the-flywheel). |

All log files use `0o600` permissions and 10MB rotation. Enforcement hooks are applied to agents that write code (leader, coder, ops). Context and observability hooks are applied to all agents.

## The Flywheel

The `prompts/flywheel.md` prompt turns your session history into configuration improvements. Every time you correct the agent — "no, I meant...", "try again but...", "stop, use X instead" — that's a signal. The flywheel reads recent session logs, identifies correction patterns, cross-references your existing steering/skills/agent configs, and proposes targeted changes to prevent recurrence.

```
Sessions ──▶ Corrections ──▶ Patterns ──▶ Config changes
    ▲                                         │
    └──────────── better behavior ────────────┘
```

It works in five phases:

1. **Session analysis** — scans `~/.kiro/sessions/cli/*.jsonl` for correction events (explicit corrections, cancelled turns, repeated instructions, frustration signals)
2. **Pattern recognition** — groups corrections by theme, filters out one-offs, focuses on patterns across 2+ sessions
3. **Cross-reference** — checks existing steering docs, skills, and agent prompts for coverage gaps or weak rules
4. **Propose changes** — writes a structured report with evidence (quoted user messages) and draft config content
5. **Interactive review** — walks through each proposal for your approval before applying

Run it periodically — weekly works well — or whenever you notice the agent repeating a mistake you've already corrected:

```bash
kiro-cli chat
# then type: run flywheel
```

Each approved change makes the next run's report shorter. Over time, the agent accumulates your preferences and conventions as persistent configuration rather than ephemeral context.

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
| [context7](https://github.com/upstash/context7) | Upstash (open source) | leader, coder, reviewer, security-reviewer |
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
- **Add prompts**: Drop a markdown file in `prompts/` — reusable workflows you can invoke by name during a chat session
- **Add hooks**: Create executable scripts in `hooks/` and reference them in agent JSON configs under the appropriate trigger (`preToolUse`, `postToolUse`, `stop`, `agentSpawn`, `userPromptSubmit`)
- **Change models**: Edit the `model` field in each agent's JSON config. Available GA models: `auto`, `claude-opus-4.5`, `claude-sonnet-4.5`, `claude-sonnet-4.0`, `claude-haiku-4.5`
- **Change default agent**: Edit `chat.defaultAgent` in `settings/cli.json`

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.

# Kiro CLI Multi-Agent Development Sample

A sample configuration for multi-agent development workflows using [Kiro CLI](https://kiro.dev). Demonstrates how to set up a team of specialized AI agents that collaborate through a plan-driven development process.

## Why Multi-Agent?

A single agent with one massive prompt works for small tasks. It breaks down on real projects:

- **Context window frugality** — each agent carries only the context it needs. The docs agent doesn't load IaC verification rules; the coder doesn't carry review checklists. Smaller context means fewer hallucinations and lower cost.
- **Blast radius containment** — a coder that goes off the rails can't merge its own work. The reviewer is a separate agent with a separate context that never saw the implementation reasoning, so it catches what self-review misses.
- **Cost optimization through model tiering** — planning and review require strong reasoning (Opus). Implementation is mechanical (Sonnet). Documentation is low-risk prose (Haiku). You pay for intelligence only where it moves the needle.
- **Parallelism** — independent tasks fan out to separate agents via `/spawn`. A six-file feature doesn't serialize through one agent's context; three coders work simultaneously.
- **Independent evolvability** — tune one agent's prompt without destabilizing others. Add a new specialist (e.g., a performance reviewer) without touching the existing team.

> **⚠️ This configuration is for Kiro CLI v3.** It uses the v3 model: standalone hook files
> (`hooks/*.json`), Markdown agent profiles, and capability-based `permissions.yaml`. Run sessions with
> the v3 engine (`kiro-cli --v3`).
>
> The previous v2 configuration (JSON agents with embedded hooks, camelCase triggers) is archived on the
> [cli-v2 branch](https://github.com/aws-samples/sample-kiro-cli-multiagent-development/tree/cli-v2).

> **Disclaimer**: This repository is provided as an example only. The agent configurations, steering rules, and workflows are starting points, not production-ready defaults. You should review, adjust, and tailor them to fit your own project requirements, team conventions, and security posture.

## Overview

This repo provides a sample `.kiro` configuration with six agents that work together:

| Agent | Role | Model |
|-------|------|-------|
| **architect** | Researches, designs plans, sequences work, delegates work | claude-opus-5 |
| **reviewer** | Reviews implementations for correctness, quality, and maintainability | claude-opus-5 |
| **security-reviewer** | Reviews implementations exclusively for security vulnerabilities and misconfigurations | claude-opus-5 |
| **coder** | Implements features and writes tests from plans | claude-sonnet-4.6 |
| **ops** | Infrastructure, CI/CD, containers, and documentation | claude-sonnet-4.6 |
| **docs** | Writes and updates documentation from completed plan work | claude-haiku-4.5 |

> **Note:** This roster reflects the author's environment and the models available in it. Substitute a model available to you by editing each agent's `model:` field, and check `kiro-cli chat --list-models` for what your account offers. The tiering pattern matters more than these specific IDs. At the time of writing `claude-opus-5` is an experimental preview rather than generally available; `claude-opus-4.6`, `claude-sonnet-4.6`, `claude-sonnet-4`, `claude-haiku-4.5`, and `auto` are the stable choices.

The `architect` agent orchestrates the workflow: it writes plans, breaks work into parallelized task groups, delegates to `coder` and `ops` for implementation via `/spawn`, then sends the results to `reviewer` and `security-reviewer` for feedback. Once reviews pass, `docs` updates the documentation. This loop continues until all groups are complete.

### Cost Considerations

A typical `standard`-depth feature runs through: architect (Opus, planning) → coder/ops (Sonnet, implementation) → reviewer (Opus) → security-reviewer (Opus) → docs (Haiku). That's 3-4 Opus-tier calls, 1-2 Sonnet calls, and 1 Haiku call per feature cycle.

For lower-ceremony work, use `prototype` depth (skips the code-review requirement, and the security review too when no auth or data boundary is crossed). `patch` depth produces no plan at all and routes bug fixes to the `diagnose` flow — but it still runs both review gates, so it is cheaper in artifacts rather than in scrutiny. The [depth system](docs/depth-levels.md) exists specifically to let you dial cost and ceremony to match the risk of what you're building.

## How It Works

```
architect (plan + research) → coder + ops (build in parallel via /spawn) → reviewer (verify) → security-reviewer (security audit) → docs (update documentation) → architect (next group or fix)
```

1. **Plan** — `architect` researches the problem, looks up SDK/framework APIs from live documentation, writes a plan, and creates a task plan. If the work touches authentication, authorization, secrets, data handling/migration, or network exposure, a security design review runs before implementation begins.
2. **Build** — `architect` uses `/spawn` to delegate task groups to `coder` and/or `ops` subagents in parallel
3. **Review** — `reviewer` analyzes the implementation for correctness and quality
4. **Security Review** — after the general review passes, `security-reviewer` audits for vulnerabilities, misconfigurations, and compliance risks
5. **Document** — `docs` updates README, architecture docs, and inline documentation to reflect the changes
6. **Fix** — if either review fails, `architect` creates fix tasks and loops back to build

Before any implementation begins, the architect conducts SDK/framework research using AWS documentation and Context7 to verify API signatures, import paths, and constructor conventions. Findings are written to a `docs/tech.md` in *your* project — created at runtime, not shipped in this repo — so subagents code against verified contracts, not assumed APIs.

> **Worked example**: See [docs/example-plan/](docs/example-plan/) for a complete prototype-depth plan showing the full artifact lifecycle — spec, design review (2 cycles), code review (2 cycles), security review (2 cycles), and decisions log.

## Quick Start

1. Install [Kiro CLI](https://kiro.dev) (v3 engine required)

2. From your project root, clone this repo into `.kiro/`:

```bash
# run this from the project root, NOT from inside .kiro/
git clone https://github.com/aws-samples/sample-kiro-cli-multiagent-development.git .kiro
chmod +x .kiro/hooks/scripts/*.sh .kiro/tools/*.sh
```

3. Start a chat with the architect agent — **from the project root**, not from `.kiro/`:

```bash
kiro-cli --v3 chat --agent architect
```

The working directory matters. v3 discovers hooks at `<workspace>/.kiro/hooks/`, the agents declare their
resources as `file://.kiro/steering/…`, and each hook manifest invokes its script as
`.kiro/hooks/scripts/…`. All three are relative to where you start Kiro, so launching from inside
`.kiro/` makes them resolve to `.kiro/.kiro/…` and silently find nothing.

Everything is workspace-relative by design, so the clone above is the whole install — no symlinks, no
copying into your home directory. If you would rather run this as your global config for every project,
see [Global config](docs/global-config.md), which lists the paths to rewrite.

> **Verify the hooks are live before trusting them.** Two hooks in this repo's history shipped broken and
> silently exited 0 on every write while the README said they blocked things. Run
> `bash .kiro/hooks/scripts/test-write-guards.sh` and the other suites after cloning; they exercise the
> scripts directly. To confirm the *manifests* are wired, start a session and check that
> `10-validate-environment` prints your tool versions at session start.

4. After a few sessions, run the [flywheel](docs/flywheel.md) to see what the system learned from your corrections:

```
/flywheel
```

## Repository Structure

```
├── agents/                  # Agent profiles (Markdown: YAML frontmatter + system prompt)
│   ├── architect.md         # Architect: config (model, MCP, tools) + prompt in one file
│   ├── coder.md
│   ├── ops.md
│   ├── reviewer.md
│   ├── security-reviewer.md
│   └── docs.md
├── hooks/                   # Standalone v3 hook manifests (apply to all agents in the workspace)
│   ├── 00-guard-destructive-commands.json
│   ├── 01-check-secrets.json
│   ├── 02-guard-secret-reads.json
│   ├── 03-guard-config-writes.json
│   ├── 10-validate-environment.json
│   ├── 20-git-context.json
│   ├── 30-check-dependency-pins.json
│   ├── 50-rtk-compress.json
│   └── scripts/             # Hook implementation scripts + their test suites
├── tools/                   # Not hooks — gate helpers and static checks you run directly
│   ├── check-hook-paths.sh            # Hook manifests point at scripts that exist (+ `--self-test`)
│   ├── mirror-to-public.sh            # Maintainer sync: private -> this sample, with divergences protected
│   ├── check-review-verdict.sh        # The review/security/design gate's `Verify` command
│   ├── check-steering-allocation.sh   # Per-agent steering allocation (+ `--self-test`)
│   ├── check-rule-copies.sh           # Minimalism-ladder copies in sync (+ `--self-test`)
│   └── test-check-review-verdict.sh   # 26 cases pinning the verdict parser
├── settings/
│   ├── cli.json             # Kiro CLI feature toggles (thinking, subagents, context indicator)
│   └── permissions.yaml     # Capability-based permission policy
├── steering/                # Rule files, no `inclusion:` frontmatter — delivered per agent via `resources:` (9 files)
│   ├── delivery-workflow.md     # Plan-driven delivery loop with 4 depth levels
│   ├── cli-execution.md     # RTK compression + AWS discover-via-MCP/execute-via-CLI
│   ├── doc-research.md      # SDK/framework API verification before implementation
│   ├── minimalism.md        # Write the least code that fully works (YAGNI ladder)
│   ├── testing.md           # Test-first development with depth scaling
│   └── ...                  # (4 more: artifact-locations, virtual-environments, documentation, dependency-versions)
├── skills/                  # Domain-specific capability and workflow skills (13 total)
│   ├── design/              # Interactive plan drafting
│   ├── execute/             # Resume and run the current plan
│   ├── diagnose/            # Test-first bug fixing
│   ├── flywheel/            # Analyze sessions → propose config improvements
│   └── ...                  # (harvest-debt + 8 capability skills)
└── docs/                    # Detailed documentation
    └── example-plan/        # Complete worked example (prototype-depth plan + all review artifacts)
```

## Key Concepts

| Concept | What it is |
|---------|------------|
| **Agents** | Who does what. Each is a single `.md` file: YAML frontmatter (model, tools, MCP, resources) + system prompt body. |
| **Steering** | 9 rule files. The orchestrator loads all of them plus any project-level `.kiro/steering/`; each subagent loads an explicit subset — see [agent design](docs/agent-design.md). |
| **Slash commands** | `/spawn`, `/goal`, and `/<skill-name>` are Kiro CLI features, not files in this repo — you will not find a `commands/` directory. `/spawn` delegates to subagents, `/goal` runs a self-verifying loop ([details](docs/depth-levels.md)), and a manual skill is invoked as `/<its-name>`. |
| **Skills** | Domain knowledge agents reference. Workflow skills (`design`, `execute`, `diagnose`, `flywheel`, `harvest-debt`) are invoked by name; capability skills are consulted as needed. |
| **Plans** | Runtime artifacts in `.kiro/delivery/YYYY-MM-DD-<slug>/`. Contain design decisions, task plans, reviews. Declare a [depth level](docs/depth-levels.md) that scales ceremony. |
| **Hooks** | Lifecycle triggers ([details](docs/hooks.md)). Fire on file save, tool use, session start, etc. Two action types: shell commands (control via exit code) or agent prompts (injected context). |
| **Permissions** | Capability-based rules ([details](docs/permissions.md)). `deny > ask > allow`. Hot-reloaded. |

### The Flywheel (Self-Improvement Loop)

The system learns from your corrections. Every time you redirect the agent ("no, use X instead", "try again but...") that's a signal. The [flywheel skill](docs/flywheel.md) scans session transcripts, identifies correction patterns, and proposes targeted config changes to prevent recurrence.

```
Sessions ──▶ Corrections ──▶ Patterns ──▶ Config changes
    ▲                                         │
    └──────────── better behavior ────────────┘
```

Single-agent workflows forget between sessions. The flywheel encodes lessons into durable config so the same mistake doesn't recur.

## Detailed Documentation

| Topic | Link |
|-------|------|
| Plan depth levels (patch, prototype, standard, production) | [docs/depth-levels.md](docs/depth-levels.md) |
| Hooks reference (triggers, exit codes, coverage, test suites) | [docs/hooks.md](docs/hooks.md) |
| Permissions deep-dive (capabilities, patterns, scope) | [docs/permissions.md](docs/permissions.md) |
| The flywheel (self-improvement loop) | [docs/flywheel.md](docs/flywheel.md) |
| Observability and debugging | [docs/observability.md](docs/observability.md) |
| Agent design decisions (model tiering, steering allocation, cost) | [docs/agent-design.md](docs/agent-design.md) |
| MCP server configuration | [docs/mcp-servers.md](docs/mcp-servers.md) |
| Moving to global configuration | [docs/global-config.md](docs/global-config.md) |

## Customization

- **Add agents**: Create a new `<name>.md` in `agents/` with YAML frontmatter + system prompt
- **Add steering rules**: Drop a markdown file in `steering/` with **no `inclusion:` frontmatter**, then add it to the `resources:` list of each agent that needs it. `inclusion: manual` is never delivered and `inclusion: always` goes to every agent — see [agent design](docs/agent-design.md). Only the orchestrator uses a glob, so a new file reaches it automatically and reaches no subagent until you list it. Run `bash tools/check-steering-allocation.sh` after editing.
- **Add skills**: Create a `<name>/SKILL.md` in `skills/` with frontmatter (`name` and `description`)
- **Add hooks**: Create a `hooks/<NN-name>.json` manifest (and a script in `hooks/scripts/` for command actions)
- **Adjust permissions**: Edit `settings/permissions.yaml` (`deny > ask > allow`)
- **Change models**: Edit the `model` field in each agent's frontmatter. Run `kiro-cli chat --list-models` to see available options.
- **Change the default agent**: pass `--agent <name>` when starting a session. `settings/cli.json` ships feature toggles only — there is no `defaultAgent` or model key in this configuration.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.

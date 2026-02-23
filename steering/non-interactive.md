---
inclusion: always
---

# Non-Interactive Execution

All scripts, commands, and tools executed by agents MUST run non-interactively with zero user prompts. No command may block waiting for stdin, confirmation, or interactive input.

## Rules

1. **No interactive prompts** — always pass flags to suppress confirmation (e.g., `-y`, `--yes`, `--no-input`, `--force`, `-f`, `DEBIAN_FRONTEND=noninteractive`)
2. **No TTY assumptions** — never rely on a terminal being attached; commands must work in headless/CI contexts
3. **Pipe-safe** — if a command detects a non-TTY stdin and changes behavior (e.g., pagers), use flags to disable it (e.g., `--no-pager`, `GIT_PAGER=cat`)
4. **Provide all inputs via arguments or files** — never rely on interactive wizards, `read` prompts, or editor pop-ups (e.g., use `git commit -m` not `git commit`)
5. **Fail loudly on missing input** — if a required value isn't provided, exit with a non-zero code and a clear error message rather than prompting

## Banned Commands

NEVER use these — they are interactive by default and cannot be made non-interactive reliably:

| Banned | Use Instead |
|--------|-------------|
| `npm create` / `npm init <pkg>` | `npx --yes <create-pkg>` with all options as CLI flags |
| `npm init` (no args) | `npm init -y` |
| `git commit` (no -m) | `git commit -m "msg"` |
| `aws configure` | Use env vars or `--cli-input-json` |
| `terraform apply` (no flag) | `terraform apply -auto-approve` |

## Scaffolding Tools — Layered Interactivity

Tools invoked via `npx` have TWO layers of prompts:
1. **npx itself** — "Need to install package X. Ok to proceed?" → solved by `npx --yes`
2. **The scaffolded tool** — may have its own interactive prompts (project name, template selection, overwrite confirmation)

You MUST handle BOTH layers. `npx --yes` only solves layer 1.

**To handle layer 2**: pass ALL options as CLI arguments so the tool has nothing left to ask. If the tool prompts about a non-empty directory, ensure the directory is empty or doesn't exist before running.

Example — Vite:
```bash
# WRONG — npm create is always interactive
npm create vite@latest

# WRONG — npx --yes only suppresses the install prompt, not vite's own prompts
npx --yes create-vite@latest .

# RIGHT — all options provided, target directory must be empty or not exist
npx --yes create-vite@latest my-app --template react-ts
```

## Common Patterns

| Tool | Interactive | Non-Interactive |
|------|-----------|-----------------|
| apt | `apt install foo` | `apt-get install -y foo` |
| pip | `pip install` | `pip install --no-input` |
| npm | `npm init` | `npm init -y` |
| git | `git commit` | `git commit -m "msg"` |
| aws cli | `aws configure` | Use env vars or `--cli-input-json` |
| terraform | `terraform apply` | `terraform apply -auto-approve` |
| cdk | `cdk deploy` | `cdk deploy --require-approval never` |
| docker | `docker system prune` | `docker system prune -f` |
| npx | `npx create-foo` | `npx --yes create-foo` |
| vite | `npm create vite@latest` | `npx --yes create-vite@latest my-app --template react-ts` |

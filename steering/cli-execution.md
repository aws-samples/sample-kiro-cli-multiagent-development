# CLI Execution: RTK + AWS

## RTK (token compression)

- Prefix read-heavy, side-effect-free commands with `rtk` — e.g. `rtk cargo test`, `rtk git log`,
  `rtk git status`, `rtk npm run build`, `rtk pytest`, `rtk grep -r foo .`, `rtk ls`, `rtk tree`,
  `rtk diff`. RTK compresses their output 60–90% before it enters context.
- A `rtk-compress` hook auto-compresses read-only, rtk-supported commands even if the prefix is
  forgotten; mutating/unsupported commands run normally.
- NEVER prefix mutating or destructive commands with `rtk` (`git push`, `git commit`, `rm`,
  `npm install/publish`, deploys, `terraform apply`, `kubectl apply/delete`). Run those as normal
  commands so they pass through the permission and guard checks.

## Scratch space and deletes

`permissions.yaml` **denies** recursive delete (`rm -r`, `rm -rf`) outside the OS temp directories,
and there is no `ask` to fall back on — a denied command is refused outright and you are told why.
This is deliberate: it is what lets a run proceed unattended instead of parking on an approval
prompt.

So do not reach for `rm -r` at all:

- Create scratch space with `mktemp -d`, which lands under `/tmp` or `/var/folders`, and **leave it**.
  The OS reclaims it. Cleaning up after yourself is not worth a denied command and a retry.
- Delete individual files with `rm -f <path>` when you must — that is allowed.
- Never `rm -r` a relative path (`cd /tmp && rm -rf build`) or a variable (`rm -rf "$T"`). Neither
  can be resolved by a shell pattern, so both are denied even when the target is genuinely scratch.
- If you believe a recursive delete is genuinely required, stop and say so rather than trying
  spellings. Being refused twice for the same reason is the stop rule, not a prompt to get creative.

The same applies to the rest of the deny list — force-push, `git reset --hard`, `git rebase`,
`terraform destroy`, `kubectl delete`, `docker prune`, `chmod -R`/`chown -R`, and any shell command
touching `.kiro/settings`, `.kiro/hooks`, or `permissions.yaml`. These are refusals, not prompts.
Read config files with `read_file` instead of `cat`.

## AWS

There is no built-in AWS tool. Work with AWS in two steps:

1. **Discover** — use the **AWS Knowledge MCP server** to find the right service/API/CLI command and
   read the relevant documentation (parameters, ARNs, required IAM actions).
2. **Execute** — run the actual `aws` CLI command in the shell. Read-only calls
   (`describe-*`, `list-*`, `get-*`, `s3 ls`) are auto-compressed by RTK; write/mutating calls run
   normally and prompt per `permissions.yaml`.

Prefer least-privilege and verify parameters/permissions against the MCP docs before executing.

## Non-Interactive Execution

All scripts, commands, and tools executed by agents MUST run non-interactively with zero user prompts. No command may block waiting for stdin, confirmation, or interactive input.

### Rules

1. **No interactive prompts** — always pass flags to suppress confirmation (e.g., `-y`, `--yes`, `--no-input`, `--force`, `-f`, `DEBIAN_FRONTEND=noninteractive`)
2. **No TTY assumptions** — never rely on a terminal being attached; commands must work in headless/CI contexts
3. **Pipe-safe** — if a command detects a non-TTY stdin and changes behavior (e.g., pagers), use flags to disable it (e.g., `--no-pager`, `GIT_PAGER=cat`)
4. **Provide all inputs via arguments or files** — never rely on interactive wizards, `read` prompts, or editor pop-ups (e.g., use `git commit -m` not `git commit`)
5. **Fail loudly on missing input** — if a required value isn't provided, exit with a non-zero code and a clear error message rather than prompting

### Banned Commands

NEVER use these — they are interactive by default and cannot be made non-interactive reliably:

| Banned | Use Instead |
|--------|-------------|
| `npm create` / `npm init <pkg>` | `npx --yes <create-pkg>` with all options as CLI flags |
| `npm init` (no args) | `npm init -y` |
| `git commit` (no -m) | `git commit -m "msg"` |
| `aws configure` | Use env vars or `--cli-input-json` |
| `terraform apply` (no flag) | `terraform apply -auto-approve` |

### Scaffolding Tools — Layered Interactivity

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

### Common Patterns

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

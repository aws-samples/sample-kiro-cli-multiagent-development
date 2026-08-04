# Hooks

Hooks are standalone JSON manifests in `hooks/` that fire at lifecycle trigger points. They apply to all agents in the workspace. This page covers each hook in detail.

Each hook manifest follows the format `{ "version": "v1", "hooks": [ ... ] }`. Each hook has a `trigger`, an optional `matcher` (regex on tool name / file path / prompt text), and an `action`:

- **`command`** runs a shell script; receives the hook event as JSON on stdin; exit `0` = allow, `2` = block (PreToolUse/UserPromptSubmit only), anything else = warn.
- **`agent`** appends a prompt string to the model context (no subprocess).

> v3 hooks apply to **all agents in the workspace**: there is no per-agent hook scoping. Numeric file prefixes are organizational only. `Stop` fires at **session end** (not per turn).

## Enforcement (PreToolUse: block before damage)

| Manifest | Matcher | Purpose | Coverage |
|----------|---------|---------|----------|
| `00-guard-destructive-commands.json` | `shell \| execute_bash \| execute_cmd \| run_command` | Blocks `rm -rf /`, `DROP TABLE`, `terraform destroy` (without `-target`), force-pushes, `kubectl delete namespace`, etc. Strips a leading `rtk`/`rtk run`/`rtk proxy` before matching so wrapped commands are still caught. | Blocks ordinary destructive-command spellings. Command-string parsing has inherent limits — see Known gaps below. |
| `01-check-secrets.json` | `fs_write \| write \| str_replace \| fs_append` | Blocks writes containing AWS keys, private keys, GitHub/Slack tokens, or generic API-key patterns. Skips `.md` files entirely (Markdown is most of what these repos write). | Matches credential-shaped tokens on any line not containing canonical AWS documentation placeholders. Pattern: `AKIA[0-9A-Z]{16}`, private key headers, `gh[pousr]_`, `xox[bpras]-`, `sk-...`, etc. |
| `02-guard-secret-reads.json` | `read_file \| read_files` | Blocks reads of credential stores: `~/.ssh/`, `~/.aws/credentials`, `~/.aws/sso/cache/`, `~/.config/gh/hosts.yml`, `~/.gnupg/`, `~/.git-credentials`, and files matching `*.pem`, `*.key`, `*.p12`, `*.jks`, `*.ovpn`, `.kdbx`, `.env*`. | Hook-only protection on the `fs_read` path; `shell: allow` means `cat ~/.aws/credentials` bypasses it. See `settings/permissions.yaml` comment for details. |
| `03-guard-config-writes.json` | `shell \| execute_bash \| execute_cmd \| run_command` | Blocks shell commands that combine a config path (`~/.kiro/settings`, `~/.kiro/hooks`, `permissions.yaml`) with a write construct. Resolves write targets rather than guessing token positions. | Blocks the ordinary forms (`>`, `>>`, `cp`, `mv`, `rsync`, `sed -i`, `tee`, `unlink`, `find -delete`, `tar -C`, interpreter one-liners). **Not a security boundary** — see Known gaps below. |
| `30-check-dependency-pins.json` | `fs_write \| write \| str_replace \| fs_append` | Blocks writes to dependency files with unpinned versions. Matcher: files named `requirements*.txt` (not `dev-requirements.txt` or `test-requirements.txt`) and `package.json`, `pyproject.toml`, `Cargo.toml`. | Checked: pip/poetry, npm, Rust Cargo. NOT checked: Gemfile, go.mod, pom.xml, Pipfile. These ecosystems are governed by `dependency-versions.md` but have no hook. |

> The v2 `config-drift-guard` hook is replaced by a `permissions.yaml` `ask` rule on `~/.kiro/**` (engine-enforced on fs_write) plus the new `03-guard-config-writes` hook (shell-only guard on execute_bash).

## Performance (PreToolUse: intercept and compress)

| Manifest | Purpose |
|----------|---------|
| `50-rtk-compress.json` | Runs **read-only, rtk-supported** commands (`git status/log/diff`, `cargo test`, `ls`, `grep`, read-only `aws describe-*/list-*/get-*`, ...) through [RTK](https://github.com/rtk-ai/rtk) and returns the compressed output. Mutating/metachar/unsupported commands pass through to the normal gated path. |

## Context (SessionStart / UserPromptSubmit: inject information)

| Manifest | Trigger | Purpose |
|----------|---------|---------|
| `10-validate-environment.json` | `SessionStart` | Checks required tools are installed and prints versions. |
| `20-git-context.json` | `UserPromptSubmit` | Injects a one-line git summary into agent context. |

## Maintenance scripts — `tools/`, not `hooks/scripts/`

These four are **not hooks**. No manifest references any of them; they are gate helpers and static
checks you or an agent run directly. They live in `tools/` for a concrete reason: the
`permissions.yaml` rule that makes editing the enforcement surface require a keystroke matches any
shell command whose text contains `.kiro/hooks`, and it cannot tell a read from an execute. While
these scripts lived under `hooks/scripts/`, the mandatory review gate's own `Verify` command tripped
that rule and prompted mid-review — so a gate that must run unattended could not. Moving them out
removes the collision without carving an exception into the guard.

| Script | Purpose | Test Suite |
|--------|---------|------------|
| `check-rule-copies.sh` | Verifies the minimalism ladder block stays identical across `steering/minimalism.md` and its copies in `coder.md`/`ops.md`. Resolves its own tree from `BASH_SOURCE`, so it checks the repo it ships in. Run manually or in CI. | `bash tools/check-rule-copies.sh --self-test` — asserts the comparison detects a drifted copy. |
| `check-steering-allocation.sh` | Static check on the per-agent steering allocation: no file may carry `inclusion: always`, the orchestrator must declare both steering globs, no subagent may declare any, all five subagents must agree on one path prefix, and every declared file must exist and match the table in [agent design](agent-design.md). | `bash tools/check-steering-allocation.sh --self-test` — 9 synthetic trees, each of which must be rejected or accepted as expected. |
| `mirror-to-public.sh` | Syncs the maintainer's private `~/.kiro` to this sample, applying the standing transformations (orchestrator name, and the path forms that differ because the private tree *is* `~/.kiro` while this one is cloned to `<project>/.kiro`) and refusing to touch the files that diverge on content. `--check` reports drift and writes nothing. Exists because the sync was being done with ad-hoc `sed` and overwrote a deliberate divergence — the public copy of `skills/aws-technical-docs/SKILL.md` links the public AWS style guide, and a bulk mirror replaced it with a path to a local PDF. | `bash tools/mirror-to-public.sh --self-test` — 12 assertions covering each transformation, the skip list, and two cases that must be left alone. |
| `check-hook-paths.sh` | Asserts every manifest's `action.command` uses the workspace-relative `.kiro/hooks/scripts/` prefix, names a script that exists, and that the script is executable. Exists because all 8 manifests once used absolute `~/` paths that did not resolve under the documented project-local install — and a missing script exits 127, which the engine treats as "warn and proceed". | `bash tools/check-hook-paths.sh --self-test` — 4 trees: reverted prefix, missing script, non-executable script. |
| `check-review-verdict.sh` | The review/security-review gate's `Verify` command. Exits 0 only if the newest cycle section records `PASS` — any heading containing the word, including the design gate's `## Security Design Review — Cycle N`; exits 2 on a missing or unfilled verdict, so "no verdict" never reads as approval. | `bash tools/test-check-review-verdict.sh` — 26 cases, including the three shapes that defeated the original `grep -i 'verdict.*pass'`, the design-gate heading form that defeated the first cycle scoping, and the bold/heading prose and nested-fence shapes that defeated the first verdict-vs-prose split. |
| `test-guard-secret-reads.sh` | 14 test cases covering the secret-read guard, including case-variant bypasses and the plural `paths[]` shape. Run: `bash hooks/scripts/test-guard-secret-reads.sh`. | Confirms the guard blocks credential stores and allows safe reads. |
| `test-guard-config-writes.sh` | 59 test cases covering the config-write guard against command-string variations, output suppression, variable indirection, interpreter one-liners, etc. Run: `bash hooks/scripts/test-guard-config-writes.sh`. | Confirms the guard blocks the ordinary write-to-config spellings. |
| `test-write-guards.sh` | 23 test cases confirming `check-secrets` and `check-dependency-pins` both fire correctly. Run: `bash hooks/scripts/test-write-guards.sh`. | Confirms field-name fixes and `fs_append` matcher additions took effect. |

## Known gaps

Two of these guards inspect command text, and command text is chosen by whoever wrote the instruction —
which in a prompt-injection threat model is the adversary. They raise the cost of a first-order injected
instruction. **Neither is a security boundary, and neither should be described as one.**

`guard-config-writes.sh` resolves write targets (expanding `~`/`$HOME`, substituting variables, globbing,
tracking `cd` across segments, and treating interpreter one-liners as indivisible) rather than guessing
token positions. Three security review cycles found and closed bypasses in it. What still gets through:

- heredoc bodies used as code (`bash << 'EOF' … EOF`)
- command substitution (`cd "$(echo ~/.kiro/hooks)"`), brace expansion, partial quoting
- multi-hop variable indirection (`A=~; B=$A/.kiro; …`)
- creating a symlink and writing through it in one command, since `realpath` cannot resolve a link that
  does not exist yet
- any writer verb not in its list — the list covers `rm`, `unlink`, `shred`, `patch`, `tar -C`,
  `unzip -d`, `ex`, `awk -i inplace`, and the Python/Node write verbs, but the general property (any
  binary that can open a file for writing is a mutator) is not enumerable

The engine-enforced `shell: ask` rule on config paths in `permissions.yaml` is the layer that shares none
of these bypass classes, because the engine matches before the shell runs. Treat the hook as a tripwire
and that rule as the control. See [Permissions](permissions.md).

## Two of these hooks had never fired

Worth knowing as a cautionary note about verifying guards rather than trusting them.
`check-secrets` and `check-dependency-pins` read `tool_input.content` — a field no write tool sends
(`fs_write` and `fs_append` send `text`; `str_replace` sends `oldStr`/`newStr`). Both exited 0 on every
write and had never inspected anything, while the README stated they blocked such writes. Manifest
matchers and `bash -n` both looked correct; only executing them revealed it.

That is why the four test suites are committed rather than left as prose, and why each carries a canary
case that fails loudly if the guard silently reverts to a no-op. Run them after touching anything under
`hooks/`.

## Notes

- Telemetry/log files use `0o600` permissions and never store transcript bodies or secrets.
- These scripts can be run on any machine to verify the guards work in your environment: `bash ~/.kiro/hooks/scripts/<name>.sh`.

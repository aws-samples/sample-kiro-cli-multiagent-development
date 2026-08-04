# Permissions

The capability-based permission policy lives at `settings/permissions.yaml`. Install it to `~/.kiro/settings/permissions.yaml` for user scope.

Rules resolve `deny > ask > allow`. The policy is **hot-reloaded**: changes take effect immediately without restarting the session.

## Transient Comments Warning

The comments in `permissions.yaml` are transient. When you answer an approval prompt with "always allow", the CLI rewrites `permissions.yaml` to persist your choice and strips every comment in it. Verified 2026-07-25, when one click removed 54 lines of rationale. All rules survived, and appended `allow` entries cannot weaken anything (since `deny > ask > allow`). But the explanation of *why* each rule exists does not survive. Keep that reasoning somewhere else: this page is that copy.

Neither the `guard-config-writes` hook nor the config-path `shell: ask` rule prevents this, because both guard *agent* writes rather than the CLI's own preference-persistence path. Prefer a one-time allow on that file.

## Capability Breakdown

### Baseline

- Baseline `allow` on six capabilities: `builtin`, `shell`, `mcp`, `subagent`, `web_fetch`, and `web_search`, so normal work is not noisy. The `deny` rules below are more restrictive and win.
- `web_fetch` and `web_search` are declared explicitly rather than left to the engine default. An undeclared capability falls through to that default, and if the default resolves to `ask` it reintroduces exactly the blocking this policy exists to remove.
- Non-obvious: **`shell` is evaluated under its own capability.** `builtin: allow` alone does *not* auto-approve shell commands, which is why an explicit `shell: allow` is present.
- If you have ever answered a prompt with "always allow", expect appended `allow` rules — possibly including `shell: ["*"]` and `rm *`. They are redundant against the baseline and cannot weaken anything, since `deny > ask > allow`.

### fs_read

No **deny** rules. An `fs_read` deny glob makes `grep_search` and `file_search` fail closed — verified empirically: with a deny rule active, a markdown-scoped content search and a filename search for `tasks.md` were both refused despite touching no secret. `list_directory` was unaffected. The scan tools present a pattern scope the engine cannot prove disjoint from the deny globs, so it refuses the whole call. Secret-read protection lives in the `02-guard-secret-reads` PreToolUse hook instead, which binds the `fs_read` capability only.

Shell-based reads like `cat ~/.aws/credentials` bypass this hook, because it binds `read_file`/`read_files` only. This is parity with the `fs_read` deny rule it replaced, which was also capability-scoped — so it is not a regression, but secret-read protection here is **not complete**, and no rule in this file makes it complete. See [Hooks](hooks.md) for the guard's coverage and known gaps.

### fs_write

- **deny** on key material: `**/*.pem`, `**/*.key`, `**/id_rsa`, `**/id_ed25519`, `**/.ssh/**`, `**/.aws/credentials`
- **deny** on workspace secrets: `**/.env`, `**/.env.*`, `**/secrets/**`
- **deny** on the enforcement surface: `~/.kiro/settings/**`, `~/.kiro/hooks/**`, `~/.kiro/agents/**` — the policy, the hooks that guard it, and the profiles that declare tools, MCP servers, and permissions
- Deliberately **not** denied: `~/.kiro/steering/`, `skills/`, `docs/`. Those are prose, they are git-tracked, and the flywheel edits them by design. The residual is that injected content could rewrite a steering rule; the git history is the audit trail.

### shell

- **deny** on destructive git/infra/container commands: force-push, `reset --hard`, `clean -f`, `checkout --force`, `branch -D`, `rebase`, `chmod -R`, `chown -R`, `docker prune`, `terraform destroy`, `kubectl delete`
- **deny** on config paths: `*permissions.yaml*`, `*.kiro/settings*`, `*.kiro/hooks*`. This is the engine-enforced layer behind the `guard-config-writes` hook, which is a command-string parser with bypass classes it cannot close. Shell patterns cannot tell a read from a write, so this refuses `cat ~/.kiro/settings/permissions.yaml` too — use `read_file`. It governs *agent* tool calls only; a human typing `chmod +x .kiro/hooks/scripts/*.sh` at install time is unaffected.
- **deny** on recursive delete outside the OS temp dirs, with `exclude` carve-outs for absolute `/tmp/*` and `/var/folders/*` paths
- **deny** on catastrophic commands: `mkfs`, `dd ... of=/dev/*`, `sudo rm`, `chmod 777 /`

### web_fetch

- **deny** on cloud-metadata/SSRF endpoints

## Pattern Matching Note

Shell patterns support `*` only; compound commands (`;`, `&&`, `||`, `|`) are split and evaluated per sub-command. That per-sub-command split is why `rm -r*` matched commands that merely *contained* a recursive delete somewhere in a long pipeline — the most common source of prompts in practice. The engine-enforced patterns cannot distinguish read from write, so they fire on both.

## Why there is not one `ask` rule

This policy is **zero-ask** by design, and adding an `ask` rule is a regression. The reason is mechanical, from the engine's decision function:

```js
if (effect === "deny")  return { decision: "reject", reason, policyDenial };
if (effect === "allow") return { decision: "accept" };
return await consentSerializer.serializedAsk(...);   // blocks on a human
```

`deny` hands the agent a reason and it keeps working — it can route around the refusal, log it, or mark the task blocked. `allow` is silent. Only `ask` parks the run until someone clicks, which makes unattended operation impossible by construction: one recursive delete in a scratch directory and the run sleeps until morning.

This is **stricter**, not looser. An `ask` on `rm -rf ~/important` is a prompt a tired human approves at 3am; a `deny` is a refusal. Every rule that used to prompt now either allows the action or refuses it, and the judgement was made once, deliberately, here.

Two consequences worth accepting up front:

1. **Some legitimate idioms are refused.** `cd /tmp && rm -rf build` (relative target) and `T=$(mktemp -d); rm -rf "$T"` (variable target) are both denied, because no shell pattern can resolve them. The answer is not a looser rule — `steering/cli-execution.md` tells agents to create scratch space with `mktemp -d` and leave it for the OS to reclaim, which removes the need for the operation.
2. **The guard hooks carry more weight.** They are subprocesses, not tool calls, so they never prompt and they fire on every shell invocation regardless of these rules. They are what makes the permissive half of this policy acceptable. See [Hooks](hooks.md).

Verifying what a rule actually did, rather than guessing:

```bash
grep -h 'acp.policy-eval.complete' ~/.kiro/logs/*/kiro.log | tail
# -> acp.policy-eval.complete {"toolId":"run_command","effect":"ask","capability":"shell"}
```

`acp.policy-eval.matched-rule` names the planific rule but is `debug`-level — run with `KIRO_LOG_LEVEL=debug` when you need it.

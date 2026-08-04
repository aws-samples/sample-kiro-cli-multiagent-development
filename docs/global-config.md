# Moving to Global Configuration

> If you just want to try this in one project, skip this page. The Quick Start in the README has everything you need.

If you want these agents available across all your projects, promote the config to `~/.kiro/`:

## Copy Everything

```bash
# Back up any existing global config first — this overwrites in place
[ -d ~/.kiro ] && cp -r ~/.kiro ~/.kiro.bak.$(date +%Y%m%d-%H%M%S)

cp -r agents/ steering/ skills/ hooks/ settings/ ~/.kiro/
chmod +x ~/.kiro/hooks/scripts/*.sh
```

## Update Resource Paths

Each agent's `resources:` block mixes two forms, and only one of them needs changing.

**Already global — leave alone.** The skill globs are declared twice, once project-relative and once
home-absolute, so they resolve under either install:

```yaml
skill://.kiro/skills/**/SKILL.md
skill://~/.kiro/skills/**/SKILL.md
```

The orchestrator's steering globs are declared the same way, for the same reason — and its
project-relative glob is what lets a project ship its own `.kiro/steering/` rules. Keep both.

**Needs changing — the subagents' explicit steering lists.** Each subagent lists the planific files it
needs, project-relative. Prefix each with `~/`:

```yaml
# Before (project-local)
- file://.kiro/steering/delivery-workflow.md
- file://.kiro/steering/cli-execution.md

# After (global)
- file://~/.kiro/steering/delivery-workflow.md
- file://~/.kiro/steering/cli-execution.md
```

One command does it for all five subagents:

```bash
sed -i '' 's|file://\.kiro/steering/|file://~/.kiro/steering/|g' \
  ~/.kiro/agents/{coder,ops,reviewer,security-reviewer,docs}.md
```

Then confirm nothing broke:

```bash
bash ~/.kiro/tools/check-steering-allocation.sh
```

Do **not** run that `sed` against `architect.md` — it would collapse its dual globs into one and cut off
project-level steering.

The permission policy is now at `~/.kiro/settings/permissions.yaml` (copied above). Note that the CLI
rewrites this file when you answer an approval prompt with "always allow", stripping its comments — see
[Permissions](permissions.md).

## Hooks in a global install

**Agents are user-global** (`~/.kiro/agents/`) and load everywhere. Hooks do too: the engine's
`globalHookRoots` is always the home directory, so every manifest in `~/.kiro/hooks/` loads in *every*
workspace regardless of what the project contains. Verified against the shipped agent server
(`standalone-hook-loader.ts` / `hooks-module-cache.ts`), and observed directly — a session whose
workspace had no `.kiro/` still logged `v2 hooks loaded 8 standalone hooks`. **No symlink is needed, and
an earlier version of this page was wrong to claim otherwise.**

What does need changing is the script path inside each manifest. This repo ships them
workspace-relative, because the documented install is a clone into `<project>/.kiro`:

```json
"action": { "type": "command", "command": ".kiro/hooks/scripts/guard-secret-reads.sh" }
```

Hook commands run with `cwd` set to the workspace root (`CommandAction.execute` spawns with
`cwd: opts.cwd`, where `cwd` is `workspacePaths[0]`), so that resolves in a project-local install and
breaks in a global one — in any project that has no `.kiro/hooks/scripts/`. Rewrite the eight manifests
to absolute paths when you go global:

```bash
sed -i '' 's|"\.kiro/hooks/scripts/|"~/.kiro/hooks/scripts/|g' ~/.kiro/hooks/*.json
```

Then confirm they still parse and that the scripts are where the manifests now say:

```bash
for f in ~/.kiro/hooks/*.json; do python3 -m json.tool "$f" >/dev/null || echo "INVALID $f"; done
grep -h '"command"' ~/.kiro/hooks/*.json
```

A missing script exits 127, which the engine treats as "warn and proceed" — and on the non-blocking
triggers (`SessionStart`, `PostToolUse`) that message is discarded, so a wrong path here degrades
silently. After rewriting, start a session and check that `10-validate-environment` prints your tool
versions; that is the cheapest positive signal that the manifests are wired.

The `tools/` scripts are invoked by the workflow rather than by a manifest, and `steering/delivery-workflow.md`
names them as `.kiro/tools/check-review-verdict.sh`. In a global install, change those three `Verify`
lines to `~/.kiro/tools/check-review-verdict.sh`.

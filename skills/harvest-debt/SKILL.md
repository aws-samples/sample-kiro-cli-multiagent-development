---
name: harvest-debt
description: "Collect SHORTCUT: markers across the codebase into a tech-debt ledger at docs/debt.md. Use when asked to harvest debt, audit technical shortcuts, or inventory deferred simplifications."
---

# Harvest Debt

Collect the intentional `SHORTCUT:` markers scattered through the codebase into a single debt ledger, so deferred simplifications stay visible instead of becoming permanent.

## Process

1. **Find the markers.** Search the repo for `SHORTCUT:` comments (skip `.git`, build output, vendored deps, and `node_modules`):
   ```bash
   grep -rn "SHORTCUT:" . \
     --include='*.py' --include='*.ts' --include='*.tsx' --include='*.js' \
     --include='*.go' --include='*.rs' --include='*.java' --include='*.rb' \
     --include='*.sh' --include='*.tf' --include='*.yaml' --include='*.yml' \
     2>/dev/null | grep -v node_modules
   ```
   Adjust the extensions to the project's languages. If the project has none, say so and stop.

2. **Parse each marker** into: file:line, the ceiling (the named limitation), and the upgrade path. A marker that names no ceiling is itself a finding — flag it as "unspecified ceiling — needs a real limit named or removal."

3. **Write the ledger** to `docs/debt.md` (create it if missing). Group by area/module. Use this shape:

   ```markdown
   # Tech Debt Ledger

   _Generated from `SHORTCUT:` markers on <date>. Each entry is an intentional simplification with a known ceiling._

   | Location | Shortcut | Ceiling (when it breaks) | Upgrade path |
   |----------|----------|--------------------------|--------------|
   | `db.py:42` | global lock | throughput-bound past ~N writes/s | per-account locks |
   ```

   Preserve any entries already in the ledger that still have a matching marker; drop entries whose marker no longer exists (the debt was paid) and note them under a "Resolved since last harvest" list.

4. **Summarize**: total markers, how many have unspecified ceilings, and the 3–5 highest-risk items (those whose ceiling is closest to being hit given the project's actual scale).

5. **Offer the next step, do not take it.** Recommend whether the debt warrants a hardening plan. If the user agrees, hand off to the `design` skill to create a plan whose tasks upgrade the highest-risk shortcuts — do not start implementing here. Harvesting is read-only except for writing the ledger.

## Rules

- Read-only on source code — this skill only writes/updates `docs/debt.md`.
- Do not "fix" shortcuts while harvesting; collection and remediation are separate steps.
- Markers without a named ceiling are debt-on-debt — call them out so they get a real limit or get removed.

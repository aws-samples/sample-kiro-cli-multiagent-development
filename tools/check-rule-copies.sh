#!/bin/bash
# Maintenance check: keep the minimalism LADDER block in sync across its copies.
# Canonical: <root>/steering/minimalism.md
# Copies:    <root>/agents/coder.md, <root>/agents/ops.md
#
# The ladder is duplicated into the implementer agent prompts on purpose (a literal
# in-prompt copy is more reliable than steering alone for a rule this load-bearing).
# Duplication drifts — this check fails loudly when a copy diverges from canonical.
#
# <root> is resolved from this script's own location, NOT from a hardcoded ~/.kiro.
# The earlier version hardcoded ~/.kiro, which meant that running it from a clone of the
# public sample silently checked the maintainer's private global config instead of the
# tree it shipped in: it printed OK while verifying nothing about that tree, and exited 1
# for anyone who had no ~/.kiro at all. A check that cannot see the thing it claims to
# check is worse than no check. `--self-test` below proves this one can fail.
#
# Usage:
#   bash hooks/scripts/check-rule-copies.sh              # check this tree
#   bash hooks/scripts/check-rule-copies.sh --self-test  # prove the check can fail
# Exit 0 = all copies match. Exit 1 = drift, missing block, or self-test failure.

set -uo pipefail

SELF_TEST=0
[[ "${1:-}" == "--self-test" ]] && SELF_TEST=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ! -d "$ROOT/steering" || ! -d "$ROOT/agents" ]]; then
    # Fallback only: a manifest may invoke this by absolute path from elsewhere.
    if [[ -d "$HOME/.kiro/steering" && -d "$HOME/.kiro/agents" ]]; then
        ROOT="$HOME/.kiro"
        echo "note: script location has no steering/+agents/; falling back to $ROOT" >&2
    else
        echo "FAIL: no steering/ + agents/ found relative to the script or at ~/.kiro" >&2
        exit 1
    fi
fi

ROOT="$ROOT" SELF_TEST="$SELF_TEST" python3 << 'PYEOF'
import os, re, sys, tempfile, shutil

ROOT = os.environ["ROOT"]
SELF_TEST = os.environ["SELF_TEST"] == "1"
BEGIN, END = "<!-- LADDER:BEGIN -->", "<!-- LADDER:END -->"

def paths(root):
    return (os.path.join(root, "steering", "minimalism.md"),
            [os.path.join(root, "agents", "coder.md"),
             os.path.join(root, "agents", "ops.md")])

def extract(path):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        return None, f"cannot read {path}: {e}"
    m = re.search(re.escape(BEGIN) + r"\n(.*?)\n" + re.escape(END), text, re.DOTALL)
    if not m:
        return None, f"no LADDER block found in {path}"
    return m.group(1).strip(), None

def check(root, quiet=False):
    canonical, copies = paths(root)
    canon, err = extract(canonical)
    if err:
        if not quiet: print(f"FAIL: canonical block missing — {err}", file=sys.stderr)
        return 1
    drift = []
    for p in copies:
        block, err = extract(p)
        if err: drift.append(err)
        elif block != canon: drift.append(f"LADDER block in {p} differs from canonical")
    if drift:
        if not quiet:
            print("FAIL: minimalism ladder is out of sync:", file=sys.stderr)
            for d in drift: print(f"  - {d}", file=sys.stderr)
            print("Re-copy the block between the LADDER markers from minimalism.md into each copy.",
                  file=sys.stderr)
        return 1
    if not quiet:
        print(f"OK: LADDER block in sync across {len(copies)} copies + canonical.")
        print(f"    tree: {root}")
    return 0

if SELF_TEST:
    # Copy the tree, mutate one ladder copy, and require the check to fail on it.
    tmp = tempfile.mkdtemp(prefix="ladder-selftest-")
    try:
        for d in ("steering", "agents"):
            shutil.copytree(os.path.join(ROOT, d), os.path.join(tmp, d))
        clean = check(tmp, quiet=True)
        victim = os.path.join(tmp, "agents", "coder.md")
        t = open(victim).read().replace(BEGIN + "\n", BEGIN + "\nMUTATED\n", 1)
        open(victim, "w").write(t)
        dirty = check(tmp, quiet=True)
        if clean == 0 and dirty == 1:
            print("OK: self-test passed — the check detects a mutated ladder copy.")
            sys.exit(0)
        print(f"FAIL: self-test broken (clean={clean} expected 0, mutated={dirty} expected 1)",
              file=sys.stderr)
        sys.exit(1)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

sys.exit(check(ROOT))
PYEOF

exit $?

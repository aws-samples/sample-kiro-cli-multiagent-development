#!/bin/bash
# Maintenance check: keep the minimalism LADDER block in sync across copies.
# Canonical: steering/minimalism.md
# Copies:    agents/coder.md, agents/ops.md
#
# The ladder is duplicated into the implementer prompts on purpose (a literal
# in-prompt copy is more reliable than relying on steering injection alone).
# Duplication drifts — this check fails loudly when a copy diverges from canonical.
#
# Paths resolve relative to this script, so it works whether the config is
# installed at .kiro/ (local) or ~/.kiro/ (global). Run manually
# (`hooks/check-rule-copies.sh`) or wire it into CI.
# Exit 0 = all copies match. Exit 1 = drift or missing block.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

ROOT="$ROOT" python3 << 'PYEOF'
import os, re, sys

ROOT = os.environ["ROOT"]
CANONICAL = os.path.join(ROOT, "steering", "minimalism.md")
COPIES = [
    os.path.join(ROOT, "agents", "coder.md"),
    os.path.join(ROOT, "agents", "ops.md"),
]
BEGIN, END = "<!-- LADDER:BEGIN -->", "<!-- LADDER:END -->"

def extract(path):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        return None, f"cannot read {path}: {e}"
    m = re.search(re.escape(BEGIN) + r"\n(.*?)\n" + re.escape(END), text, re.DOTALL)
    if not m:
        return None, f"no LADDER block found in {path}"
    return m.group(1).strip(), None

canon, err = extract(CANONICAL)
if err:
    print(f"FAIL: canonical block missing — {err}", file=sys.stderr)
    sys.exit(1)

drift = []
for path in COPIES:
    block, err = extract(path)
    if err:
        drift.append(err)
    elif block != canon:
        drift.append(f"LADDER block in {path} differs from canonical ({CANONICAL})")

if drift:
    print("FAIL: minimalism ladder is out of sync:", file=sys.stderr)
    for d in drift:
        print(f"  - {d}", file=sys.stderr)
    print("Re-copy the block between the LADDER markers from minimalism.md into each copy.", file=sys.stderr)
    sys.exit(1)

print(f"OK: LADDER block in sync across {len(COPIES)} copies + canonical.")
sys.exit(0)
PYEOF

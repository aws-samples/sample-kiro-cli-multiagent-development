#!/bin/bash
# Hook: Block writes to agent config files unless explicitly approved.
# Trigger: preToolUse on fs_write
# Exit 0 = allow, Exit 2 = block (returns STDERR to LLM)
#
# Protected paths: ~/.kiro/steering/, ~/.kiro/skills/, ~/.kiro/agents/
# To allow config writes, set KIRO_ALLOW_CONFIG_WRITES=1 or run the
# flywheel prompt (which should instruct the user to approve changes).

set -euo pipefail

[ "${KIRO_ALLOW_CONFIG_WRITES:-}" = "1" ] && exit 0

EVENT=$(cat)

# Use realpath to resolve symlinks and normalize path traversal
_HOOK_EVENT="$EVENT" python3 << 'PYEOF'
import json, sys, os

KIRO_DIR = os.path.realpath(os.path.expanduser("~/.kiro"))
PROTECTED = [
    os.path.join(KIRO_DIR, "steering"),
    os.path.join(KIRO_DIR, "skills"),
    os.path.join(KIRO_DIR, "agents"),
]

try:
    event = json.loads(os.environ['_HOOK_EVENT'])
except (KeyError, json.JSONDecodeError) as e:
    print(f"Hook error: failed to parse event: {e}", file=sys.stderr)
    sys.exit(1)

inp = event.get('tool_input', {})
ops = inp.get('ops', [inp])

for op in ops:
    path = op.get('path', '')
    if not path:
        continue
    resolved = os.path.realpath(os.path.expanduser(path))
    for protected in PROTECTED:
        if resolved.startswith(protected + os.sep) or resolved == protected:
            print("BLOCKED: Writing to Kiro configuration files requires explicit approval.", file=sys.stderr)
            print(f"File: {resolved}", file=sys.stderr)
            print("Ask the user to approve this change before proceeding.", file=sys.stderr)
            sys.exit(2)

sys.exit(0)
PYEOF

exit $?

#!/bin/bash
# Hook: Block dangerous shell commands that could cause irreversible damage.
# Trigger: preToolUse on execute_bash
# Exit 0 = allow, Exit 2 = block (returns STDERR to LLM)

set -euo pipefail

EVENT=$(cat)

_HOOK_EVENT="$EVENT" python3 << 'PYEOF'
import json, sys, re, os

RULES = [
    # (description, pattern that BLOCKS, pattern that ALLOWS as exception)
    (
        'Recursive delete of root/home',
        re.compile(r'rm\s+.*-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*\s+(/\s|/\s*$|~\s|~\s*$|\$HOME\s|\$HOME\s*$)', re.MULTILINE),
        None,
    ),
    (
        'SQL destructive operation',
        re.compile(r'\b(DROP\s+(TABLE|DATABASE)|TRUNCATE\s+TABLE)\b', re.IGNORECASE),
        None,
    ),
    (
        'Terraform destroy without target',
        re.compile(r'terraform\s+destroy\b'),
        re.compile(r'terraform\s+destroy\s+.*-target\b'),
    ),
    (
        'Docker system prune',
        re.compile(r'docker\s+system\s+prune\b'),
        None,
    ),
    (
        'Disk format or raw write',
        re.compile(r'\b(mkfs\b|dd\s+if=.*/dev/)'),
        None,
    ),
    (
        'Force push to protected branch',
        re.compile(r'git\s+push\s+.*--force.*\b(main|master|production)\b'),
        None,
    ),
    (
        'Delete critical Kubernetes namespace',
        re.compile(r'kubectl\s+delete\s+namespace\s+(kube-system|production|default)\b'),
        None,
    ),
]

try:
    event = json.loads(os.environ['_HOOK_EVENT'])
except (KeyError, json.JSONDecodeError) as e:
    print(f"Hook error: failed to parse event: {e}", file=sys.stderr)
    sys.exit(1)

inp = event.get('tool_input', {})
command = inp.get('command', '')

if not command:
    sys.exit(0)

for desc, block_pat, allow_pat in RULES:
    if block_pat.search(command):
        if allow_pat and allow_pat.search(command):
            continue
        print(f'BLOCKED: {desc}', file=sys.stderr)
        print(f'Command: {command[:200]}', file=sys.stderr)
        print('This command could cause irreversible damage. Ask the user for explicit approval.', file=sys.stderr)
        sys.exit(2)

sys.exit(0)
PYEOF

exit $?

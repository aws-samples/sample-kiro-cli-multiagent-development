#!/bin/bash
# Hook: Block dangerous shell commands that could cause irreversible damage.
# Trigger: PreToolUse on execute_bash
# Exit 0 = allow, Exit 2 = block (returns STDERR to LLM)

set -euo pipefail

EVENT=$(cat)

_HOOK_EVENT="$EVENT" python3 << 'PYEOF'
import json, sys, re, os

RULES = [
    # (description, pattern that BLOCKS, pattern that ALLOWS as exception)
    (
        'Recursive delete of root/home',
        re.compile(r'rm\s+.*-[a-zA-Z]*(?:[rR][a-zA-Z]*f|f[a-zA-Z]*[rR])[a-zA-Z]*\s+(/\s|/\s*$|~\s|~\s*$|\$HOME\s|\$HOME\s*$)', re.MULTILINE),
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
        re.compile(r'git\s+push.*\s+(?:-f|\s-f\s|--force(?:-with-lease)?)(\s|$)'),
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

# SHORTCUT: strip leading rtk/rtk run/rtk proxy prefix so wrapped commands are still guarded.
# This is needed because RTK passes commands through unfiltered (rtk run = sh -c raw).
# Without stripping, 'rtk git push --force' would bypass the git --force pattern.
# The guard should block dangerous commands regardless of how they're invoked.
if command:
    command = re.sub(r'^(rtk(?:\s+(?:run|proxy))?)\s+', '', command, count=1)

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

#!/bin/bash
# Hook: Block writes containing secrets (API keys, private keys, tokens).
# Trigger: preToolUse on fs_write
# Exit 0 = allow, Exit 2 = block (returns STDERR to LLM)

set -euo pipefail

EVENT=$(cat)

_HOOK_EVENT="$EVENT" python3 << 'PYEOF'
import json, sys, re, os

ALLOWLISTED_EXTENSIONS = {'.md', '.example', '.sample', '.template'}
ALLOWLISTED_LINE_PATTERNS = re.compile(r'EXAMPLE|PLACEHOLDER|<your-|TODO|xxx|changeme', re.IGNORECASE)

SECRET_PATTERNS = [
    ('AWS Access Key', re.compile(r'AKIA[0-9A-Z]{16}')),
    ('AWS Secret Key', re.compile(r'(?:aws_secret_access_key|secret_access_key|AWS_SECRET)\s*[:=]\s*["\']?[A-Za-z0-9/+=]{40}', re.IGNORECASE)),
    ('Private Key', re.compile(r'-----BEGIN\s+(?:RSA\s+|EC\s+|DSA\s+|OPENSSH\s+)?PRIVATE\s+KEY-----')),
    ('GitHub Token', re.compile(r'gh[ps]_[a-zA-Z0-9]{36,}')),
    ('Slack Token', re.compile(r'xox[bpras]-[a-zA-Z0-9\-]+')),
    ('Generic API Key', re.compile(r'api[_\-]?key\s*[:=]\s*["\'][a-zA-Z0-9]{20,}["\']', re.IGNORECASE)),
    ('Generic Token', re.compile(r'(?:auth_token|access_token|bearer)\s*[:=]\s*["\'][a-zA-Z0-9_\-\.]{20,}["\']', re.IGNORECASE)),
]

try:
    event = json.loads(os.environ['_HOOK_EVENT'])
except (KeyError, json.JSONDecodeError) as e:
    print(f"Hook error: failed to parse event: {e}", file=sys.stderr)
    sys.exit(1)

inp = event.get('tool_input', {})
ops = inp.get('ops', [inp])

blocked = False
for op in ops:
    path = op.get('path', '')
    content = op.get('content', '')
    if not path or not content:
        continue

    ext = os.path.splitext(path)[1].lower()
    if ext in ALLOWLISTED_EXTENSIONS:
        continue

    findings = []
    for line_num, line in enumerate(content.splitlines(), 1):
        if ALLOWLISTED_LINE_PATTERNS.search(line):
            continue
        for name, pattern in SECRET_PATTERNS:
            if pattern.search(line):
                preview = line.strip()[:80]
                findings.append(f'  line {line_num}: {name} — {preview}')
                break

    if findings:
        print(f'BLOCKED: Potential secrets detected in {os.path.basename(path)}.', file=sys.stderr)
        print('Remove secrets and use environment variables or a secrets manager:', file=sys.stderr)
        for f in findings[:10]:
            print(f, file=sys.stderr)
        if len(findings) > 10:
            print(f'  ... and {len(findings) - 10} more', file=sys.stderr)
        blocked = True

sys.exit(2 if blocked else 0)
PYEOF

exit $?

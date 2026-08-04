#!/bin/bash
# Hook: Block writes containing secrets (API keys, private keys, tokens).
# Trigger: PreToolUse on fs_write
# Exit 0 = allow, Exit 2 = block (returns STDERR to LLM)

set -euo pipefail

EVENT=$(cat)

_HOOK_EVENT="$EVENT" python3 << 'PYEOF'
import json, sys, re, os

ALLOWLISTED_EXTENSIONS = {'.md', '.example', '.sample', '.template'}
# NO line-level allowlist. An earlier version skipped any line containing EXAMPLE, TODO,
# PLACEHOLDER, xxx, changeme, or <your-, which meant a real credential was exempted by a
# trailing `# TODO rotate this` — verified live: the identical line with and without that
# comment was blocked and then allowed. Placeholder detection now happens at the TOKEN
# level below (see the EXAMPLE test in the findings loop), which is strictly more precise:
# it exempts AWS's canonical documentation keys, whose own text ends in EXAMPLE, without
# exempting anything based on the surrounding prose.
#
# The other former allowlist words cannot cause a false positive on their own —
# <your-key-here> and PLACEHOLDER do not match any SECRET_PATTERNS entry, since the
# generic patterns require 20+ alphanumerics inside quotes.

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
    # Read every shape the write tools actually send. `fs_write` sends `text`;
    # `str_replace` sends `oldStr`/`newStr`; `fs_append` sends `text`. Nothing sends
    # `content` — reading only that made this hook a silent no-op from the day it was
    # written (found by security review 2026-07-24, proven by writing an AKIA-shaped
    # key with no interception). Keep `content` first for the batched `ops` shape.
    content = op.get('content') or op.get('text') or op.get('newStr') or ''
    if not path or not content:
        continue

    ext = os.path.splitext(path)[1].lower()
    if ext in ALLOWLISTED_EXTENSIONS:
        continue

    findings = []
    for line_num, line in enumerate(content.splitlines(), 1):
        for name, pattern in SECRET_PATTERNS:
            m = pattern.search(line)
            if m:
                # Exempt the match only if the credential-shaped token ITSELF declares
                # that it is fake — AWS's canonical documentation keys end in the word
                # EXAMPLE, as do their secret-key counterparts. This is deliberately
                # narrower than the line-level allowlist above: a real key sitting on a
                # line that merely mentions the word "example" is still reported.
                if 'EXAMPLE' in m.group(0).upper():
                    continue
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

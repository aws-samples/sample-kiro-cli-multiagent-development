#!/bin/bash
# Hook: Log turn summaries for the flywheel prompt to consume.
# Trigger: stop (fires after each assistant response)
# Writes lightweight JSONL to ~/.kiro/flywheel-log.jsonl

set -euo pipefail

EVENT=$(cat)

_HOOK_EVENT="$EVENT" python3 << 'PYEOF'
import json, sys, time, os

LOG_PATH = os.path.realpath(os.path.expanduser("~/.kiro/flywheel-log.jsonl"))
MAX_LOG_BYTES = 10 * 1024 * 1024  # 10 MB

try:
    event = json.loads(os.environ['_HOOK_EVENT'])
except (KeyError, json.JSONDecodeError) as e:
    print(f"Hook error: failed to parse event: {e}", file=sys.stderr)
    sys.exit(1)

response = event.get('assistant_response', '')
cwd = event.get('cwd', '')

if not response.strip():
    sys.exit(0)

entry = {
    'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'cwd': cwd,
    'response_length': len(response),
    'response_preview': response[:500],
}

os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)

# Rotate if log exceeds max size
try:
    if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > MAX_LOG_BYTES:
        rotated = LOG_PATH + '.old'
        if os.path.exists(rotated):
            os.remove(rotated)
        os.rename(LOG_PATH, rotated)
except OSError:
    pass

# Open with restrictive permissions (owner read/write only)
fd = os.open(LOG_PATH, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
try:
    os.chmod(LOG_PATH, 0o600)
except OSError:
    pass
with os.fdopen(fd, 'a') as f:
    f.write(json.dumps(entry) + '\n')
PYEOF

exit 0

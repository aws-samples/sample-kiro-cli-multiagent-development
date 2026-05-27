#!/bin/bash
# Hook: Lightweight turn index for flywheel analysis.
# Trigger: stop (fires after each assistant response)
# Writes one minimal JSONL entry per turn to ~/.kiro/flywheel-log.jsonl
#
# Purpose: an INDEX of recent assistant turns, not a full transcript.
# Keep entries small (<300 chars preview). Full text lives in session JSONLs.
#
# Pairs with flywheel-correction.sh (userPromptSubmit) — that hook is the
# correction-detection trigger; this hook just records what came before.

set -euo pipefail

EVENT=$(cat)

_HOOK_EVENT="$EVENT" python3 << 'PYEOF'
import json, sys, time, os

LOG_PATH = os.path.realpath(os.path.expanduser("~/.kiro/flywheel-log.jsonl"))
MAX_LOG_BYTES = 5 * 1024 * 1024  # 5 MB — smaller now that we're storing less per entry
PREVIEW_CHARS = 200

try:
    event = json.loads(os.environ['_HOOK_EVENT'])
except (KeyError, json.JSONDecodeError) as e:
    print(f"Hook error: failed to parse event: {e}", file=sys.stderr)
    sys.exit(1)

response = event.get('assistant_response', '')
cwd = event.get('cwd', '')

if not response.strip():
    sys.exit(0)

# Take a tail preview too — corrections often respond to something the agent
# said at the end ("I'll do X") rather than the opening sentence.
head = response[:PREVIEW_CHARS].replace('\n', ' ').strip()
tail = response[-PREVIEW_CHARS:].replace('\n', ' ').strip() if len(response) > PREVIEW_CHARS * 2 else ''

entry = {
    'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'cwd': cwd,
    'len': len(response),
    'head': head,
}
if tail:
    entry['tail'] = tail

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

fd = os.open(LOG_PATH, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
try:
    os.chmod(LOG_PATH, 0o600)
except OSError:
    pass
with os.fdopen(fd, 'a') as f:
    f.write(json.dumps(entry) + '\n')
PYEOF

exit 0

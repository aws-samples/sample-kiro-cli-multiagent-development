#!/bin/bash
# Hook: Detect correction signals in user prompts and log them for flywheel analysis.
# Trigger: userPromptSubmit (fires when user submits a prompt)
# Writes filtered JSONL entries to ~/.kiro/flywheel-corrections.jsonl
#
# Purpose: capture only prompts that LOOK LIKE corrections, redirections, or
# frustration — not every user message. The flywheel prompt reads this file
# to find suspect events, then deep-dives into session JSONLs for full context.
#
# The hook outputs nothing on stdout (we don't want to inject anything into
# the agent context) — this is a side-channel logger only.

set -euo pipefail

EVENT=$(cat)

_HOOK_EVENT="$EVENT" python3 << 'PYEOF'
import json, sys, time, os, re

LOG_PATH = os.path.realpath(os.path.expanduser("~/.kiro/flywheel-corrections.jsonl"))
MAX_LOG_BYTES = 5 * 1024 * 1024
MAX_PROMPT_CHARS = 500

# Correction signal patterns. Each pattern carries a label so we can group later.
# Using word boundaries and reasonable specificity to avoid false positives.
SIGNALS = [
    # Explicit corrections
    ('explicit_correction', re.compile(r"\b(no|nope),?\s+(i\s+)?(meant|said|wanted|asked)\b", re.I)),
    ('explicit_correction', re.compile(r"\bthat'?s\s+(wrong|not\s+(right|correct|what))\b", re.I)),
    ('explicit_correction', re.compile(r"\b(don'?t|do\s+not)\s+(do|use|run|create|delete|change)\b", re.I)),
    ('explicit_correction', re.compile(r"\bi\s+said\b.*\bnot\b", re.I | re.DOTALL)),
    ('explicit_correction', re.compile(r"\b(actually|wait),?\s", re.I)),
    # Redirections
    ('redirect', re.compile(r"\binstead\s+(of|do|use|try)\b", re.I)),
    ('redirect', re.compile(r"\b(cancel|stop|abort)\s+(that|this)\b", re.I)),
    ('redirect', re.compile(r"\btry\s+again\b", re.I)),
    ('redirect', re.compile(r"\b(start|do)\s+over\b", re.I)),
    # Frustration / repeat
    ('repeat', re.compile(r"\bi\s+(already|just)\s+(said|told|asked)\b", re.I)),
    ('repeat', re.compile(r"\b(again|once\s+more),?\s+(but|with|please)\b", re.I)),
    ('repeat', re.compile(r"^(why|why\s+(did|are)).{0,80}\?", re.I)),
    # Quality complaints
    ('quality', re.compile(r"\b(too\s+(verbose|long|short|much|many))\b", re.I)),
    ('quality', re.compile(r"\b(stop|don'?t)\s+(making|creating|adding|using)\b", re.I)),
    ('quality', re.compile(r"\byou\s+(forgot|missed|skipped|ignored)\b", re.I)),
    ('quality', re.compile(r"\b(read|check)\s+(the|my|this)\s+\w+\s+(again|first)\b", re.I)),
    # Tool/permission redirects
    ('tool_redirect', re.compile(r"\buse\s+(\w+)\s+(instead|not)\b", re.I)),
    ('tool_redirect', re.compile(r"\b(don'?t|do\s+not)\s+(use|run|call)\b", re.I)),
    # Brevity / "just" patterns — short prompts after long agent output
    # (handled by length check below, not a regex)
]

try:
    event = json.loads(os.environ['_HOOK_EVENT'])
except (KeyError, json.JSONDecodeError) as e:
    print(f"Hook error: failed to parse event: {e}", file=sys.stderr)
    sys.exit(1)

prompt = event.get('prompt', '')
cwd = event.get('cwd', '')

if not prompt or not prompt.strip():
    sys.exit(0)

# Strip context entries that may be in the prompt body — we only want the
# user-typed message, not injected git status etc.
# Newer Kiro CLI passes only the user prompt; older versions may include
# CONTEXT ENTRY blocks. Handle both defensively.
user_text = prompt
if '--- USER MESSAGE BEGIN' in prompt:
    start = prompt.find('USER MESSAGE BEGIN ---')
    end = prompt.find('--- USER MESSAGE END')
    if start >= 0 and end > start:
        user_text = prompt[start + len('USER MESSAGE BEGIN ---'):end].strip()

# Skip very long prompts — slash commands, pasted spec contents, etc.
# Real corrections are almost always short.
if len(user_text) > 2000:
    sys.exit(0)

# Detect correction signals
matches = []
for label, pattern in SIGNALS:
    if pattern.search(user_text):
        matches.append(label)

# Brevity heuristic: very short prompts (< 60 chars) often signal a
# rephrased request after a failed attempt or a one-word correction
# ("no", "stop", "wrong file", etc.). Flag these as "terse".
is_terse = len(user_text.strip()) < 60

# Question-restart heuristic: short prompts ending with "?" after the
# agent presumably gave a long answer.
is_short_question = is_terse and user_text.strip().endswith('?')

if not matches and not is_terse:
    # No correction signals — don't log. This is the whole point: filter.
    sys.exit(0)

if is_terse and not matches:
    matches.append('terse')
if is_short_question:
    matches.append('short_question')

# Dedupe labels
matches = sorted(set(matches))

entry = {
    'ts': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'cwd': cwd,
    'signals': matches,
    'prompt': user_text[:MAX_PROMPT_CHARS],
    'prompt_len': len(user_text),
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

fd = os.open(LOG_PATH, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
try:
    os.chmod(LOG_PATH, 0o600)
except OSError:
    pass
with os.fdopen(fd, 'a') as f:
    f.write(json.dumps(entry) + '\n')
PYEOF

# Always succeed silently. We do NOT write to stdout because that would
# inject content into the agent context.
exit 0

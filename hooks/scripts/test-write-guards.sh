#!/usr/bin/env bash
# Runnable check for the two write-inspecting hooks: check-secrets and check-dependency-pins.
#
# Why this exists. Both hooks read the content of a pending write. Both originally read
# only `tool_input.content` — a field NO write tool sends (`fs_write` and `fs_append` send
# `text`; `str_replace` sends `oldStr`/`newStr`). So both exited 0 on every write and had
# never fired, while `steering/dependency-versions.md` and the public README both stated
# they block such writes. Found by security review 2026-07-24 by executing them, not by
# reading them: manifest matchers and `bash -n` both looked fine.
#
# The canary cases at the end fail loudly if either hook silently reverts to a no-op.
#
# NOTE ON THE FIXTURES: the credential-shaped test values are assembled from adjacent
# string fragments ("AKI""AXXXX...") so that this file does not itself contain a
# contiguous match. Otherwise check-secrets blocks any attempt to write this test — which
# it did, on the first try, and that is how the field-name fix was confirmed live.
#
# Usage: bash ~/.kiro/hooks/scripts/test-write-guards.sh
# Exit 0 = all cases correct. Exit 1 = at least one wrong.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS="$DIR/check-secrets.sh"
PINS="$DIR/check-dependency-pins.sh"
for f in "$SECRETS" "$PINS"; do [[ -f "$f" ]] || { echo "FAIL: missing $f"; exit 1; }; done

# Assembled at runtime — see NOTE ON THE FIXTURES above.
FAKE_KEY="aws_access_key_id = AKI""AIOSFODNN7REALKEY"
FAKE_PRIV="-----BEGIN RSA PRIV""ATE KEY-----"
FAKE_EXAMPLE="key = AKI""AIOSFODNN7EXAMPLE"

pass=0; fail=0

# probe <script> <expected_exit> <path> <field> <content> <label>
probe() {
    local script="$1" want="$2" path="$3" field="$4" body="$5" label="$6" got
    printf '{"hook_event_name":"PreToolUse","cwd":"/tmp","tool_input":%s}' \
        "$(python3 -c 'import json,sys; print(json.dumps({"path":sys.argv[1], sys.argv[2]:sys.argv[3]}))' \
            "$path" "$field" "$body")" \
        | bash "$script" >/dev/null 2>&1
    got=$?
    if [[ "$got" == "$want" ]]; then
        pass=$((pass+1)); printf '  ok    exit=%s  %-8s %-18s %s\n' "$got" "$field" "$(basename "$path")" "$label"
    else
        fail=$((fail+1)); printf '  FAIL  exit=%s (want %s)  %-8s %-18s %s\n' "$got" "$want" "$field" "$(basename "$path")" "$label"
    fi
}

echo "check-secrets.sh — every field shape the write tools actually send"
probe "$SECRETS" 2 /tmp/app/config.yml text    "$FAKE_KEY"     "key via fs_write text (was the no-op)"
probe "$SECRETS" 2 /tmp/app/config.yml newStr  "$FAKE_KEY"     "key via str_replace newStr"
probe "$SECRETS" 2 /tmp/app/config.yml content "$FAKE_KEY"     "key via batched ops content"
probe "$SECRETS" 2 /tmp/app/id_rsa     text    "$FAKE_PRIV"    "private key header"
probe "$SECRETS" 0 /tmp/app/config.yml text    "port = 8080"   "ordinary config"
probe "$SECRETS" 0 /tmp/app/notes.md   text    "$FAKE_KEY"     "markdown allowlisted by extension"
probe "$SECRETS" 0 /tmp/app/config.yml text    "$FAKE_EXAMPLE" "self-declared EXAMPLE placeholder"
probe "$SECRETS" 2 /tmp/app/config.yml text    "# see example below
$FAKE_KEY"                                                     "real key on a line after the word example"
# W3 regression cases: a line-level allowlist used to exempt these. A real credential
# with any ordinary trailing comment MUST still be reported.
probe "$SECRETS" 2 /tmp/app/config.yml text    "$FAKE_KEY  # TODO rotate before launch" "real key + TODO comment"
probe "$SECRETS" 2 /tmp/app/config.yml text    "$FAKE_KEY  # see example.txt"           "real key + 'example' comment"
probe "$SECRETS" 2 /tmp/app/config.yml text    "$FAKE_KEY  # placeholder for now"       "real key + 'placeholder' comment"
probe "$SECRETS" 2 /tmp/app/config.yml text    "$FAKE_KEY  # xxx"                       "real key + 'xxx' comment"
probe "$SECRETS" 2 /tmp/app/config.yml text    "$FAKE_KEY  # changeme"                  "real key + 'changeme' comment"
probe "$SECRETS" 2 /tmp/app/config.yml text    "$FAKE_KEY  # <your-key-here>"           "real key + '<your-' comment"

echo
echo "check-dependency-pins.sh — every field shape"
probe "$PINS" 2 /tmp/app/requirements.txt text    "requests>=2.31.0" "unpinned pip via text (was the no-op)"
probe "$PINS" 2 /tmp/app/requirements.txt newStr  "requests>=2.31.0" "unpinned pip via newStr"
probe "$PINS" 2 /tmp/app/requirements.txt content "requests>=2.31.0" "unpinned pip via ops content"
probe "$PINS" 2 /tmp/app/requirements.txt text    "boto3"            "bare package, no version"
probe "$PINS" 0 /tmp/app/requirements.txt text    "requests==2.31.0" "correctly pinned"
probe "$PINS" 2 /tmp/app/package.json     text    '{"dependencies":{"express":"^4.18.2"}}' "npm caret range"
probe "$PINS" 0 /tmp/app/package.json     text    '{"dependencies":{"express":"4.18.2"}}'  "npm exact pin"

echo
echo "canary — a known-bad write MUST block (detects a silent no-op):"
canary() {
    local script="$1" path="$2" body="$3" name="$4"
    printf '{"hook_event_name":"PreToolUse","cwd":"/tmp","tool_input":%s}' \
        "$(python3 -c 'import json,sys; print(json.dumps({"path":sys.argv[1],"text":sys.argv[2]}))' "$path" "$body")" \
        | bash "$script" >/dev/null 2>&1
    if [[ $? == 2 ]]; then pass=$((pass+1)); echo "  ok    $name is live"
    else fail=$((fail+1)); echo "  FAIL  $name did not block a known-bad write — it may be a no-op"; fi
}
canary "$SECRETS" /tmp/app/c.yml "$FAKE_KEY" "check-secrets"
canary "$PINS" /tmp/app/requirements.txt "requests>=2.31.0" "check-dependency-pins"

echo
if [[ $fail -eq 0 ]]; then echo "OK: $pass/$pass cases correct."; exit 0; fi
echo "FAILED: $fail of $((pass+fail)) cases wrong."; exit 1

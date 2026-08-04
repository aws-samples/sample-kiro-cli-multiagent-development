#!/usr/bin/env bash
# Runnable check for guard-secret-reads.sh.
#
# Why this exists: the guard is the ONLY secret-read control on the fs_read path
# (permissions.yaml deliberately carries no fs_read deny rule — a deny glob makes
# grep_search/file_search fail closed; see
# specs/2026-07-24-kiro-config-overhaul/decisions.md). A silent no-op in this
# script is therefore a total loss of protection, not a defence-in-depth gap.
#
# Two real defects motivated committing it:
#   1. The original hardening matched case-sensitively while macOS/APFS is
#      case-insensitive, so ~/.SSH/ID_RSA and key.PEM bypassed both layers.
#      The original ad-hoc test matrix was all-lowercase and missed it.
#   2. If the engine ever renames `tool_input` or `path`, collect_paths()
#      returns [] and the hook exits 0 — silently allowing everything. The
#      canary case below fails loudly if that happens.
#
# Usage: bash ~/.kiro/hooks/scripts/test-guard-secret-reads.sh
# Exit 0 = all cases behave correctly. Exit 1 = at least one case is wrong.

set -uo pipefail

GUARD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard-secret-reads.sh"
[[ -f "$GUARD" ]] || { echo "FAIL: guard not found at $GUARD"; exit 1; }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/nested"
printf 'not-a-real-key\n' > "$TMP/scratch.pem"
printf 'not-a-real-key\n' > "$TMP/UPPER.PEM"
printf 'SECRET=1\n'       > "$TMP/.env"
printf 'SECRET=1\n'       > "$TMP/.ENV"
printf 'SECRET=changeme\n'> "$TMP/.env.example"
printf 'plain text\n'     > "$TMP/plain.txt"
printf 'nothing\n'        > "$TMP/notes.md"
printf 'export AWS_SECRET_ACCESS_KEY=nope\n' > "$TMP/.envrc"
printf 'not-real\n'       > "$TMP/credentials"

pass=0; fail=0

# probe <expected_exit> <path> <label>
probe() {
    local want="$1" path="$2" label="$3" got
    printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_input":{"path":"%s"}}' "$TMP" "$path" \
        | bash "$GUARD" >/dev/null 2>&1
    got=$?
    if [[ "$got" == "$want" ]]; then
        pass=$((pass+1)); printf '  ok    %-46s exit=%s  %s\n' "$path" "$got" "$label"
    else
        fail=$((fail+1)); printf '  FAIL  %-46s exit=%s (want %s)  %s\n' "$path" "$got" "$want" "$label"
    fi
}

echo "guard-secret-reads.sh — case matrix"
echo
echo "lowercase (the original matrix):"
probe 2 "$TMP/scratch.pem"     "extension match"
probe 2 "$TMP/.env"            "dotfile match"
probe 0 "$TMP/.env.example"    "allowlisted template"
probe 0 "$TMP/plain.txt"       "ordinary file"
probe 0 "$TMP/notes.md"        "ordinary markdown"
probe 2 "$HOME/.ssh/id_rsa"    "home credential store"

echo
echo "UPPERCASE — case-insensitive filesystems reach the same bytes:"
probe 2 "$TMP/UPPER.PEM"       "extension match, folded"
probe 2 "$TMP/.ENV"            "dotfile match, folded"
probe 2 "$HOME/.SSH/ID_RSA"    "home store + basename, folded (was the bypass)"
probe 2 "$HOME/.AWS/credentials" "home store, folded"
probe 2 "$TMP/.envrc"           "direnv file (routinely holds exported credentials)"
probe 2 "$TMP/credentials"      "bare credentials file outside ~/.aws"

echo
echo "plural tool_input shape (read_files):"
printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_input":{"paths":["%s","%s"]}}' \
    "$TMP" "$TMP/plain.txt" "$TMP/scratch.pem" | bash "$GUARD" >/dev/null 2>&1
if [[ $? == 2 ]]; then
    pass=$((pass+1)); echo "  ok    paths[] containing a secret                    exit=2  blocked"
else
    fail=$((fail+1)); echo "  FAIL  paths[] containing a secret did not block"
fi

echo
echo "canary — a known secret MUST block (detects a silently no-op guard):"
printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_input":{"path":"%s"}}' "$TMP" "$HOME/.ssh/id_rsa" \
    | bash "$GUARD" >/dev/null 2>&1
if [[ $? == 2 ]]; then
    pass=$((pass+1)); echo "  ok    guard is live"
else
    fail=$((fail+1)); echo "  FAIL  guard did not block a known secret — it may be a no-op"
fi

echo
if [[ $fail -eq 0 ]]; then
    echo "OK: $pass/$pass cases correct."
    exit 0
fi
echo "FAILED: $fail of $((pass+fail)) cases wrong."
exit 1

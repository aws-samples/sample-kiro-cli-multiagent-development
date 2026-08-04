#!/usr/bin/env bash
# Sync the private config (~/.kiro) to the public sample, applying the standing mappings and
# skipping the files that diverge on purpose.
#
# Why this exists: the mirror was being done by hand with ad-hoc `sed` invocations, and that
# overwrote a deliberate divergence — `skills/aws-technical-docs/SKILL.md`, whose public copy links
# the public AWS style guide while the private copy points at a local PDF. The bad content was caught
# in a pre-commit diff read, which is not a control. This script encodes the rules instead.
#
# Two classes of difference, and the distinction is the whole point:
#
#   TRANSFORMED — same content, mechanically rewritten. The orchestrator's name, and the paths that
#                 change because the private tree IS ~/.kiro while the public tree is cloned to
#                 <project>/.kiro.
#   SKIPPED     — genuinely different content. Never overwrite these; edit each tree deliberately.
#
# Usage:
#   bash tools/mirror-to-public.sh --check    # report drift, write nothing (exit 1 if any)
#   bash tools/mirror-to-public.sh --apply    # transform and copy
#   bash tools/mirror-to-public.sh --self-test
#
# The public tree path can be overridden with KIRO_PUBLIC_TREE.

set -uo pipefail

PRIVATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLIC="${KIRO_PUBLIC_TREE:-$HOME/github/sample-kiro-cli-multiagent-development}"

# Content genuinely differs — never mirrored. Each line states why, because a skip without a reason
# becomes a mystery that someone later "fixes" by deleting it.
SKIP=(
  "README.md"                             # private documents its own security history; public is install docs
  "docs/permissions.md"                   # private carries the comment-stripping rationale; public is an overview
  "settings/permissions.yaml"             # private holds 5 CLI-added allow rules that must not be published
  "skills/aws-technical-docs/SKILL.md"    # private points at a local PDF; public links the public style guide
)

is_skipped() { local f="$1"; for s in "${SKIP[@]}"; do [[ "$f" == "$s" ]] && return 0; done; return 1; }

# Apply every mapping that turns a private file into its public counterpart.
#
# The path mappings are scoped by file type on purpose. Applying them globally corrupts
# tools/check-steering-allocation.sh, whose self-test fixtures deliberately contain
# `file://~/.kiro/steering/` to represent "the other tree's prefix" — rewriting those makes the
# wrong-prefix test compare a value against itself and silently stop testing anything. Found by this
# script's own --check reporting drift on a file that looked identical.
transform() {
    local f="$1"
    local out
    out=$(sed -e 's/SonofAnton/Architect/g' -e 's/sonofanton/architect/g' "$f")

    case "$f" in
        agents/*.md)
            # Agent resource lists: private is a global install, public is cloned to <project>/.kiro
            out=$(printf '%s\n' "$out" | sed -e 's|file://~/\.kiro/steering/|file://.kiro/steering/|g')
            ;;
        hooks/*.json)
            # Hook manifests invoke their scripts relative to the workspace root in the public tree
            out=$(printf '%s\n' "$out" | sed -e 's|"~/\.kiro/hooks/scripts/|".kiro/hooks/scripts/|g')
            ;;
        tools/check-steering-allocation.sh)
            # Name mapping only. Repair the doubled case pattern the rename produces, and leave the
            # fixture prefixes alone.
            out=$(printf '%s\n' "$out" \
                | sed -e 's/^        architect|architect) orchestrator/        architect) orchestrator/' \
                      -e 's|(architect\.md / architect\.md)|(architect.md)|')
            ;;
    esac

    # Gate commands are project-relative in the public tree. Safe everywhere: the private form only
    # appears in prose and Verify lines.
    printf '%s\n' "$out" | sed -e 's|bash ~/\.kiro/tools/|bash .kiro/tools/|g'
}

if [[ "${1:-}" == "--self-test" ]]; then
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; fail=0
    check() { # label, relative-path, input, expected-substring
        local rel="$2" got
        mkdir -p "$TMP/$(dirname "$rel")"
        printf '%s\n' "$3" > "$TMP/$rel"
        got=$(cd "$TMP" && transform "$rel")
        if [[ "$got" == *"$4"* ]]; then printf '  ok     %s\n' "$1"
        else printf '  FAIL   %s\n         got: %s\n' "$1" "$got"; fail=1; fi
    }
    refute() { # label, relative-path, input, substring-that-must-NOT-appear
        local rel="$2" got
        mkdir -p "$TMP/$(dirname "$rel")"
        printf '%s\n' "$3" > "$TMP/$rel"
        got=$(cd "$TMP" && transform "$rel")
        if [[ "$got" != *"$4"* ]]; then printf '  ok     %s\n' "$1"
        else printf '  FAIL   %s — must not contain %s\n' "$1" "$4"; fail=1; fi
    }
    echo "Self-test: mirror-to-public.sh"
    check  "orchestrator name"          steering/x.md 'delegate to sonofanton now' 'delegate to architect now'
    check  "gate command path"          steering/x.md 'bash ~/.kiro/tools/check-review-verdict.sh x' 'bash .kiro/tools/check-review-verdict.sh x'
    check  "agent steering prefix"      agents/coder.md '  - file://~/.kiro/steering/testing.md' '  - file://.kiro/steering/testing.md'
    check  "hook script path"           hooks/00-x.json '"command": "~/.kiro/hooks/scripts/x.sh"' '"command": ".kiro/hooks/scripts/x.sh"'
    check  "case-statement repair"      tools/check-steering-allocation.sh '        sonofanton|architect) orchestrator="$f" ;;' '        architect) orchestrator="$f" ;;'
    refute "checker fixtures preserved" tools/check-steering-allocation.sh "        local hpfx='file://~/.kiro/steering'" "hpfx='file://.kiro/steering'"
    refute "steering prose untouched"   steering/x.md 'the home form is file://~/.kiro/steering/x.md' 'file://.kiro/steering/x.md'
    for s in "${SKIP[@]}"; do
        if is_skipped "$s"; then printf '  ok     skip list contains %s\n' "$s"
        else printf '  FAIL   skip list missing %s\n' "$s"; fail=1; fi
    done
    if is_skipped "steering/testing.md"; then echo "  FAIL   testing.md must NOT be skipped"; fail=1
    else echo "  ok     a normal file is not skipped"; fi
    echo
    [[ $fail -eq 0 ]] && { echo "Self-test OK"; exit 0; }
    echo "Self-test FAILED"; exit 1
fi

MODE="${1:---check}"
[[ -d "$PUBLIC" ]] || { echo "FAIL: public tree not found at $PUBLIC (set KIRO_PUBLIC_TREE)"; exit 1; }
echo "private: $PRIVATE"
echo "public:  $PUBLIC"
echo

drift=0 copied=0 skipped=0
cd "$PRIVATE" || exit 1
while IFS= read -r f; do
    [[ -f "$PUBLIC/$f" ]] || continue          # public-only or private-only files are not this tool's job
    if is_skipped "$f"; then
        printf '  skip   %s\n' "$f"; skipped=$((skipped+1)); continue
    fi
    if transform "$f" | cmp -s - "$PUBLIC/$f"; then continue
    fi
    drift=$((drift+1))
    if [[ "$MODE" == "--apply" ]]; then
        transform "$f" > "$PUBLIC/$f"; printf '  synced %s\n' "$f"; copied=$((copied+1))
    else
        printf '  DRIFT  %s\n' "$f"
    fi
done < <(git ls-files | grep -E '\.(md|sh|json|yaml)$' | grep -vE '^delivery/|^issues/')

echo
printf 'shared files with drift: %d   synced: %d   skipped (deliberate divergence): %d\n' "$drift" "$copied" "$skipped"
if [[ "$MODE" != "--apply" && $drift -gt 0 ]]; then
    echo "Run with --apply to sync. Anything listed above that SHOULD differ belongs in the SKIP array."
    exit 1
fi
[[ "$MODE" == "--apply" ]] && echo "Now re-run the public tree's own checks before committing."
exit 0

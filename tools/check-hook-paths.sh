#!/usr/bin/env bash
# Asserts every hook manifest's action.command resolves under the documented install layout.
#
# Why this exists: all 8 manifests once invoked their script as `~/.kiro/hooks/scripts/<name>.sh`
# while the documented install clones this repo into `<project>/.kiro`. Hook commands run with cwd
# set to the workspace root, so the correct form here is `.kiro/hooks/scripts/<name>.sh`. Nothing
# caught the mismatch, and the failure mode is the worst kind: a missing script exits 127, which the
# engine treats as "warn and proceed", and on non-blocking triggers that message is discarded — so
# the guards silently stop enforcing while still appearing installed.
#
# What this checks:
#   - every action.command of type `command` uses the workspace-relative prefix
#   - the script it names actually exists in this repo
#   - the script is executable
#   - no manifest has drifted back to a `~/` or `$HOME` absolute path
#
# What it does NOT check: that the engine fires the hook. That needs a live session — start one and
# confirm `10-validate-environment` prints tool versions.
#
# Usage: bash tools/check-hook-paths.sh [--self-test]
# Exit 0 = all manifests conform. Exit 1 = at least one does not.

set -uo pipefail

PREFIX='.kiro/hooks/scripts/'

check_tree() {
    local root="$1" fail=0 n=0
    for m in "$root"/hooks/*.json; do
        [[ -e "$m" ]] || continue
        while IFS= read -r cmd; do
            [[ -z "$cmd" ]] && continue
            n=$((n+1))
            local name; name=$(basename "$m")
            if [[ "$cmd" == "~/"* || "$cmd" == *'$HOME'* ]]; then
                printf '  FAIL   %s: absolute path %s — breaks the project-local install\n' "$name" "$cmd"
                fail=1; continue
            fi
            if [[ "$cmd" != "$PREFIX"* ]]; then
                printf '  FAIL   %s: %s does not start with %s\n' "$name" "$cmd" "$PREFIX"
                fail=1; continue
            fi
            local rel="${cmd#"$PREFIX"}" script="$root/hooks/scripts/${cmd#"$PREFIX"}"
            if [[ ! -f "$script" ]]; then
                printf '  FAIL   %s: names %s, which does not exist\n' "$name" "$rel"
                fail=1; continue
            fi
            [[ -x "$script" ]] || { printf '  FAIL   %s: %s is not executable\n' "$name" "$rel"; fail=1; continue; }
            printf '  ok     %s -> %s\n' "$name" "$rel"
        done < <(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
for h in d.get('hooks',[]):
    a=h.get('action') or {}
    if a.get('type')=='command' and a.get('command'): print(a['command'].split()[0])
" "$m")
    done
    [[ $n -eq 0 ]] && { echo "  FAIL   no command actions found under $root/hooks"; return 1; }
    return $fail
}

if [[ "${1:-}" == "--self-test" ]]; then
    SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
    st=0
    probe() {  # $1 = label, $2 = expected rc, $3 = mutator
        local d="$TMP/$RANDOM$RANDOM"; mkdir -p "$d/hooks/scripts"
        cp "$SRC"/hooks/*.json "$d/hooks/" 2>/dev/null
        cp "$SRC"/hooks/scripts/*.sh "$d/hooks/scripts/" 2>/dev/null
        chmod +x "$d"/hooks/scripts/*.sh
        [[ -n "$3" ]] && eval "$3"
        ( check_tree "$d" >/dev/null 2>&1 ); local rc=$?
        if [[ $rc -eq $2 ]]; then printf '  ok     %s (exit %d)\n' "$1" "$rc"
        else printf '  FAIL   %s — expected %d, got %d\n' "$1" "$2" "$rc"; st=1; fi
    }
    echo "Self-test: check-hook-paths.sh"
    probe "unmodified tree passes" 0 ""
    probe "reverting one manifest to ~/ is rejected" 1 \
        "sed -i '' 's|\".kiro/hooks/scripts/|\"~/.kiro/hooks/scripts/|' \"\$d/hooks/00-guard-destructive-commands.json\""
    probe "a named-but-missing script is rejected" 1 \
        "rm -f \"\$d/hooks/scripts/git-context.sh\""
    probe "a non-executable script is rejected" 1 \
        "chmod -x \"\$d/hooks/scripts/check-secrets.sh\""
    echo
    [[ $st -eq 0 ]] && { echo "Self-test OK: 4/4"; exit 0; }
    echo "Self-test FAILED"; exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Checking hook command paths: $ROOT"
if check_tree "$ROOT"; then echo; echo "OK: every hook command resolves under $PREFIX"; exit 0; fi
echo; echo "FAILED: see above."; exit 1

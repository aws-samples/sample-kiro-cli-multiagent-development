#!/usr/bin/env bash
# RTK interceptor — compress output of READ-ONLY, rtk-supported commands before it enters context.
# Trigger: PreToolUse on shell. Returns the compressed result to the model via STDERR + exit 2.
#
# SAFETY MODEL (why this is scoped to read-only):
#   A PreToolUse command hook runs its commands as a SUBPROCESS of the hook, i.e. OUTSIDE Kiro's
#   permission layer and other hooks. So we ONLY ever execute commands that are:
#     (1) one of rtk's supported binaries, (2) free of any mutation/side-effect keyword,
#     (3) free of shell metacharacters (pipes/redirects/sub-shells), (4) for `aws`, a read verb only,
#     (5) confirmed rewritable by `rtk rewrite` (its own support oracle).
#   Anything else → exit 0, and Kiro runs it through its NORMAL gated path (permissions.yaml +
#   guard-destructive-commands), where the steering rule to prefix `rtk` still applies.
set -uo pipefail

EVENT=$(cat)
CMD=$(printf '%s' "$EVENT" | python3 -c "import json,sys;print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || true)
CWD=$(printf '%s' "$EVENT" | python3 -c "import json,sys;print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || true)
[ -z "$CMD" ] && exit 0

set -f                      # no glob expansion while tokenizing
# shellcheck disable=SC2086
set -- $CMD
set +f
first="${1:-}"; second="${2:-}"

# already rtk-wrapped, or not a supported binary → let Kiro run it normally
[ "$first" = "rtk" ] && exit 0
case " git gh glab cargo npm npx pnpm pytest ruff mypy jest vitest tsc go docker kubectl ls tree find grep diff wc aws " in
  *" $first "*) : ;;
  *) exit 0 ;;
esac

# any sign of mutation / side effect / shell metachar → do NOT intercept (Kiro's gated path handles it)
case " $CMD " in
  *push*|*install*|*publish*|*deploy*|*destroy*|*prune*|*" rm "*|*delete*|*" apply"*|*reset*|*clean*|\
  *checkout*|*rebase*|*" merge"*|*commit*|*create*|*--force*|*" -f "*|*restart*|*scale*|*exec*|\
  *">"*|*"|"*|*"&"*|*";"*|*'`'*|*'$('*) exit 0 ;;
esac

# aws: only allow read verbs (describe-/list-/get-/ s3 ls)
if [ "$first" = "aws" ]; then
  case "$CMD" in
    *describe-*|*list-*|*get-*|*"s3 ls"*|*"s3api list"*) : ;;
    *) exit 0 ;;
  esac
fi

# rtk rewrite is the authoritative support oracle. NOTE: this build EXITS 3 (not 0) when it has a
# rewrite and prints it; exits 1 with empty output when there is no rtk equivalent. So we decide on
# OUTPUT, not exit code: non-empty and starting with "rtk " means supported.
REW=$( cd "$CWD" 2>/dev/null; rtk rewrite "$CMD" 2>/dev/null )
[ -z "$REW" ] && exit 0
case "$REW" in "rtk "*) : ;; *) exit 0 ;; esac

# run the rtk-equivalent (read-only, no metachars) and hand the compressed output back to the model
OUT=$( cd "$CWD" 2>/dev/null; eval "$REW" 2>&1 ); rc=$?
printf '%s\n' "$OUT" >&2
[ "$rc" -ne 0 ] && printf '[exit %s]\n' "$rc" >&2
exit 2

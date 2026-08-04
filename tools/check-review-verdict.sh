#!/usr/bin/env bash
# Gate helper: exit 0 only if the LATEST verdict in a review file is PASS.
#
# Replaces `grep -i 'verdict.*pass' review.md`, which could not fail:
#   - review.md is append-only per cycle, so once cycle 1 passes, that stale "Verdict: PASS"
#     line keeps matching forever even when the current cycle is FAIL;
#   - the verbatim template placeholder "### Verdict: PASS | FAIL" also matched, so an
#     untouched template opened the gate.
# The gate that delivery-workflow.md calls "the most common workflow violation" was guarded by
# an assertion that always succeeded.
#
# Rules here:
#   - scope the search to everything AFTER the last cycle heading, so a newly opened cycle that
#     lists findings but has not recorded a verdict yet cannot inherit the previous cycle's PASS
#   - a cycle heading is any ATX heading containing the word "cycle" — NOT just `## Cycle N`.
#     The design gate is mandated to write `## Security Design Review — Cycle N`, which an
#     anchored `^##\s*cycle` pattern misses entirely; that silently widened the scope to the
#     whole file and restored the inheritance bug in the one file the newest gate writes to.
#     No trailing word boundary, so `## Cycle4` matches too — erring toward treating a heading
#     as a cycle boundary is the conservative direction, since it narrows the scope. `.*` rather
#     than `[^#]*` after the marker: with `[^#]*`, a heading like `## Fix Group #5 — Cycle 2` did
#     not match at all, so the scope silently widened to the whole file and the stale-PASS
#     inheritance came back. The leading `#{1,6}` already anchors this to a heading.
#   - ignore fenced code blocks, so a quoted template or a review-of-a-review is not scanned.
#     Fence matching follows the CommonMark rule (a fence closes only on a run of the SAME
#     character at least as long as the opener) because a single boolean toggle is INVERTED by
#     nesting: ````markdown wrapping ``` toggled four times and emitted the inner block as body,
#     so a quoted `### Verdict: PASS` became the operative verdict.
#   - PASS must come from a *declared* verdict: the outcome has to follow the label, as in
#     `### Verdict: PASS` or `**verdict:** pass`. Requiring only that a line START with the word
#     is not enough — `verdict\b` also matches `**Verdict rationale:** … PASS`, an ordinary thing
#     for a reviewer to write under a FAIL, and it opened the gate in heading and bold form.
#   - a line that mentions the word but does not declare an outcome can still record a FAIL, and
#     can never record a PASS. Ambiguity resolves toward the closed gate.
#   - discard any candidate offering both outcomes (an unfilled template placeholder)
#   - exit 0 on PASS, 1 on FAIL, 2 if no usable verdict exists (missing file, template never
#     filled in, or open cycle with no verdict). "No verdict" must never read as approval.
#
# Usage: bash hooks/scripts/check-review-verdict.sh <path-to-review.md>
# Test:  bash hooks/scripts/test-check-review-verdict.sh

set -uo pipefail

FILE="${1:-}"
if [[ -z "$FILE" ]]; then echo "usage: check-review-verdict.sh <review-file>" >&2; exit 2; fi
if [[ ! -f "$FILE" ]]; then echo "NO VERDICT: $FILE does not exist" >&2; exit 2; fi

# Drop fenced code blocks before any matching. A verdict inside a fence is an example, not a
# ruling. Length- and character-aware so nested fences cannot invert the state; an unclosed
# fence swallows the remainder, which fails closed.
BODY=$(awk '
{
    line = $0
    sub(/^[[:space:]]*/, "", line)
    ch = substr(line, 1, 1)
    if (ch == "`" || ch == "~") {
        n = 0
        while (substr(line, n + 1, 1) == ch) n++
        if (n >= 3) {
            if (!infence)                          { infence = 1; fc = ch; fn = n; next }
            else if (ch == fc && n >= fn)          { infence = 0; next }
        }
    }
    if (!infence) print
}' "$FILE")

# Only the newest cycle counts. review.md is append-only, so a verdict from an earlier cycle
# must never satisfy the gate for a cycle that has not recorded one.
CYCLE_LINE=$(grep -niE '^#{1,6}.*\bcycle' <<<"$BODY" | tail -1 | cut -d: -f1)
if [[ -n "$CYCLE_LINE" ]]; then
    SCOPE=$(tail -n "+$CYCLE_LINE" <<<"$BODY")
    CYCLE=$(sed -n "${CYCLE_LINE}p" <<<"$BODY" | sed -e 's/^#*[[:space:]]*//' -e 's/[[:space:]]*$//')
else
    SCOPE="$BODY"
    CYCLE=""
fi

# A declared verdict: optional heading/bold marker, the label, then the outcome. Nothing may
# come between the label and the outcome except punctuation and emphasis.
STRICT_RE='^[[:space:]]*(#{1,6}[[:space:]]*)?(\*\*[[:space:]]*)?verdict[[:space:]]*:?[[:space:]]*(\*\*)?[[:space:]]*(-|–|—)?[[:space:]]*(pass|fail)\b'
# Mentions the label but does not declare an outcome next to it.
LOOSE_RE='^[[:space:]]*(#{1,6}[[:space:]]*)?\**[[:space:]]*verdict\b'

# Strip unfilled placeholders offering both outcomes, in either order.
drop_placeholders() {
    grep -viE 'pass[[:space:]]*(\||/|or)[[:space:]]*fail' \
        | grep -viE 'fail[[:space:]]*(\||/|or)[[:space:]]*pass'
}

VERDICT=$(grep -iE "$STRICT_RE" <<<"$SCOPE" | drop_placeholders | tail -1)

if [[ -z "$VERDICT" ]]; then
    # No declared verdict. A loose mention may still record a FAIL; it may never record a PASS.
    LOOSE=$(grep -iE "$LOOSE_RE" <<<"$SCOPE" | drop_placeholders)
    if [[ -n "$LOOSE" ]] && grep -qiE '\bfail\b' <<<"$LOOSE"; then
        echo "FAIL: latest verdict is FAIL — $(grep -iE '\bfail\b' <<<"$LOOSE" | tail -1 | tr -s ' ' | sed 's/^ *//')" >&2
        exit 1
    fi
    if [[ -n "$LOOSE" ]]; then
        echo "NO VERDICT: $FILE mentions a verdict but never declares PASS or FAIL next to it" >&2
        exit 2
    fi
    if [[ -n "$CYCLE" ]]; then
        echo "NO VERDICT: '$CYCLE' has no verdict in $FILE — an earlier cycle's verdict does not count" >&2
    else
        echo "NO VERDICT: no filled-in verdict line found in $FILE (template not completed?)" >&2
    fi
    exit 2
fi

if grep -qiE '\bfail\b' <<<"$VERDICT"; then
    echo "FAIL: latest verdict is FAIL — $(tr -s ' ' <<<"$VERDICT" | sed 's/^ *//')" >&2
    exit 1
fi
if grep -qiE '\bpass\b' <<<"$VERDICT"; then
    echo "PASS: $(tr -s ' ' <<<"$VERDICT" | sed 's/^ *//')"
    exit 0
fi

echo "NO VERDICT: latest verdict line is unrecognisable — $VERDICT" >&2
exit 2

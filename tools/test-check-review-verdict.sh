#!/usr/bin/env bash
# Runnable check for check-review-verdict.sh.
#
# The first two cases are the reproductions of the original defect: with
# `grep -i 'verdict.*pass'`, both opened the review gate.
#
# Usage: bash hooks/scripts/test-check-review-verdict.sh
# Exit 0 = all cases correct.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$DIR/check-review-verdict.sh"
[[ -f "$CHECK" ]] || { echo "FAIL: missing $CHECK"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

# probe <expected_exit> <label> <<< file body
probe() {
    local want="$1" label="$2" body="$3" got
    printf '%s\n' "$body" > "$TMP/review.md"
    bash "$CHECK" "$TMP/review.md" >/dev/null 2>&1; got=$?
    if [[ "$got" == "$want" ]]; then
        pass=$((pass+1)); printf '  ok    exit=%s  %s\n' "$got" "$label"
    else
        fail=$((fail+1)); printf '  FAIL  exit=%s (want %s)  %s\n' "$got" "$want" "$label"
    fi
}

echo "check-review-verdict.sh"
echo
echo "the two original defects (both used to open the gate):"
probe 1 "cycle 1 PASS then cycle 2 FAIL -> must FAIL" \
"## Cycle 1
### Verdict: PASS

## Cycle 2
### Verdict: FAIL"
probe 2 "unfilled template placeholder -> must NOT pass" \
"## Cycle 1
### Verdict: PASS | FAIL"
probe 2 "cycle 2 open with findings, no verdict yet -> must NOT inherit cycle 1 PASS" \
"## Cycle 1
### Verdict: PASS

## Cycle 2
### Critical
- [a.py:1] regression reintroduced"

echo
echo "must PASS:"
probe 0 "single PASS"                      "### Verdict: PASS"
probe 0 "FAIL then PASS (fixed on retry)"  "## Cycle 1
### Verdict: FAIL

## Cycle 2
### Verdict: PASS"
probe 0 "bold and lowercase spelling"      "**verdict:** pass"
probe 0 "three cycles, last one PASS"      "### Verdict: FAIL
### Verdict: FAIL
### Verdict: PASS"
probe 0 "cycle 3 re-verified after fixes"  "## Cycle 1
### Verdict: FAIL

## Cycle 2
### Verdict: FAIL

## Cycle 3 — re-verified
### Verdict: PASS"

echo
echo "must NOT pass:"
probe 1 "single FAIL"                                  "### Verdict: FAIL"
probe 2 "design-gate heading form, new cycle no verdict" \
"## Security Design Review — Cycle 1
### Verdict: PASS

## Security Design Review — Cycle 2
### Critical
- [plan.md:1] threat model missing"
probe 2 "h1 cycle headings, new cycle no verdict"      "# Cycle 1
### Verdict: PASS

# Cycle 2
### Critical
- [a.py:1] regression"
probe 2 "no space before cycle number"                 "## Cycle 1
### Verdict: PASS

## Cycle4 — 2026-07-28
### Critical
- [a.py:1] regression"
probe 2 "a '#' before the word Cycle must not hide the heading" \
"## Cycle 1
### Verdict: PASS

## Fix Group #5 — Cycle 2
### Critical
- [a.py:1] regression reintroduced"
probe 1 "prose starting with Verdict cannot override a FAIL" \
"## Cycle 1
### Verdict: FAIL

Verdict rationale: recommend PASS once the two fixes land."
probe 1 "BOLD prose starting with Verdict cannot override a FAIL" \
"## Cycle 1
### Verdict: FAIL

**Verdict rationale:** recommend PASS once the two fixes land."
probe 1 "HEADING prose starting with Verdict cannot override a FAIL" \
"## Cycle 1
### Verdict: FAIL

### Verdict rationale: recommend PASS once the two fixes land"
probe 1 "bold Verdict summary cannot override a FAIL" \
"## Cycle 1
### Verdict: FAIL

**Verdict summary** — everything else would PASS."
probe 2 "a Verdict line that never states an outcome is not approval" \
"## Cycle 1
Verdict rationale: recommend PASS once the two fixes land."
probe 2 "verdict inside a code fence is an example, not a ruling" \
"## Cycle 1
Findings below.

\`\`\`
### Verdict: PASS
\`\`\`"
probe 1 "nested fence cannot smuggle a PASS past a FAIL" \
"## Cycle 1
### Verdict: FAIL

\`\`\`\`markdown
\`\`\`
### Verdict: PASS
\`\`\`
\`\`\`\`"
probe 2 "nested fence quoting a PASS is not a verdict for an open cycle" \
"## Cycle 1
### Critical
- [a.py:1] unbounded input

\`\`\`\`markdown
\`\`\`
### Verdict: PASS
\`\`\`
\`\`\`\`"
probe 1 "PASS mentioned in prose, verdict is FAIL"     "The fix makes the tests pass.
### Verdict: FAIL"
probe 2 "no verdict line at all"                       "## Cycle 1
Some findings, no verdict recorded."
probe 2 "placeholder with slash separator"             "### Verdict: PASS / FAIL"
probe 1 "template placeholder then a real FAIL"        "### Verdict: PASS | FAIL

## Cycle 1
### Verdict: FAIL"

echo
echo "missing file must NOT pass:"
bash "$CHECK" "$TMP/does-not-exist.md" >/dev/null 2>&1
if [[ $? == 2 ]]; then pass=$((pass+1)); echo "  ok    exit=2  missing file"
else fail=$((fail+1)); echo "  FAIL  missing file did not return 2"; fi

echo
if [[ $fail -eq 0 ]]; then echo "OK: $pass/$pass cases correct."; exit 0; fi
echo "FAILED: $fail of $((pass+fail)) cases wrong."; exit 1

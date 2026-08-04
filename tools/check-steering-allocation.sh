#!/usr/bin/env bash
# Static check for the per-agent steering allocation.
#
# What this DOES verify:
#   - no steering file carries an `inclusion:` frontmatter key at all. BOTH documented values break
#     this config, in opposite directions, and the second one shipped:
#       * `inclusion: always`  — injected into every agent regardless of any `resources:` list, which
#         makes the per-agent lists cosmetic.
#       * `inclusion: manual`  — NEVER auto-injected, and naming the file in `resources:` does NOT
#         count as activation. Verified with a three-way probe: a file with no frontmatter and a file
#         with `inclusion: always` were both delivered; the `inclusion: manual` file was not. This is
#         why every agent silently received ZERO steering for a period — the rules were written,
#         listed, and checked, and none of them arrived.
#     No frontmatter is the working state: the file is delivered when an agent's `resources:` names
#     it (or matches it by glob).
#   - the orchestrator IS present and DOES declare both steering globs — the project-relative
#     one so project-level steering reaches it, and the home-absolute one so the user-global
#     rules do. An earlier version only checked that non-orchestrators had no glob, so deleting
#     both globs from the orchestrator still exited 0.
#   - no other agent declares a glob
#   - every steering file an agent declares actually exists
#   - the declared allocation matches the table published in docs/agent-design.md
#
# What this CANNOT verify — read this before trusting the reductions:
#   Whether the engine honours the lists at runtime. That needs a live session per agent.
#   See "Runtime verification" at the bottom.
#
# Usage: bash hooks/scripts/check-steering-allocation.sh
#        bash hooks/scripts/check-steering-allocation.sh --self-test
# Exit 0 = all static checks pass. Exit 1 = at least one failed.

set -uo pipefail

PROJECT_GLOB='file://.kiro/steering/**/*.md'
HOME_GLOB='file://~/.kiro/steering/**/*.md'

# ---------------------------------------------------------------- self-test
# Builds synthetic trees and asserts this script's verdict on each. Guards against the
# class of bug above: a check that passes no matter what it is shown.
if [[ "${1:-}" == "--self-test" ]]; then
    SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
    st_fail=0

    make_fixture() {
        local dir="$1" variant="$2"
        mkdir -p "$dir/steering" "$dir/agents"
        local s
        for s in delivery-workflow minimalism testing doc-research dependency-versions \
                 virtual-environments cli-execution artifact-locations documentation; do
            printf -- '# %s\n\nfixture steering content\n' "$s" > "$dir/steering/$s.md"
        done
        [[ "$variant" == always ]] &&
            printf -- '---\ninclusion: always\n---\n# testing\n' > "$dir/steering/testing.md"
        [[ "$variant" == manual ]] &&
            printf -- '---\ninclusion: manual\n---\n# testing\n' > "$dir/steering/testing.md"

        emit_agent() {  # $1 = name, rest = resource lines
            local n="$1"; shift
            { echo '---'; echo "name: $n"; echo 'resources:'
              printf '  - %s\n' "$@"; echo '---'; echo "# $n"; } > "$dir/agents/$n.md"
        }
        case "$variant" in
            noglob)   emit_agent architect "skill://.kiro/skills/**/SKILL.md" ;;
            halfglob) emit_agent architect "$PROJECT_GLOB" ;;
            *)        emit_agent architect "$PROJECT_GLOB" "$HOME_GLOB" ;;
        esac
        local all=(file://.kiro/steering/delivery-workflow.md file://.kiro/steering/minimalism.md
                   file://.kiro/steering/testing.md file://.kiro/steering/doc-research.md
                   file://.kiro/steering/dependency-versions.md
                   file://.kiro/steering/virtual-environments.md
                   file://.kiro/steering/cli-execution.md
                   file://.kiro/steering/artifact-locations.md
                   file://.kiro/steering/documentation.md)
        emit_agent coder "${all[@]}"
        emit_agent ops   "${all[@]}"
        emit_agent reviewer "${all[@]:0:8}"
        emit_agent security-reviewer file://.kiro/steering/delivery-workflow.md \
            file://.kiro/steering/cli-execution.md file://.kiro/steering/artifact-locations.md \
            file://.kiro/steering/dependency-versions.md
        # Built from a single name list so the fixture cannot drift from EXPECTED the way it did
        # when dependency-versions was added to docs and every hardcoded fixture went stale.
        local pfx='file://.kiro/steering' hpfx='file://~/.kiro/steering'
        local dnames=(documentation artifact-locations cli-execution delivery-workflow dependency-versions)
        local docsf=() docsh=() s
        for s in "${dnames[@]}"; do docsf+=("$pfx/$s.md"); docsh+=("$hpfx/$s.md"); done

        emit_agent docs "${docsf[@]}"
        # One subagent left on the other tree's prefix — loads NO steering, but every file it names
        # exists under $ROOT, so the existence check alone reports ok. This shipped once; see :3.
        [[ "$variant" == oddprefix ]]   && emit_agent docs "${docsh[@]}"
        # Same agent declaring both forms.
        [[ "$variant" == mixedprefix ]] && emit_agent docs "${docsh[0]}" "${docsf[@]:1}"
        [[ "$variant" == subglob ]]     && emit_agent docs "${docsf[@]}" "$PROJECT_GLOB"
        [[ "$variant" == drift ]]       && emit_agent docs "${docsf[0]}"
        [[ "$variant" == missing ]]     && emit_agent docs "${docsf[@]:0:4}" "$pfx/nope.md"
        return 0
    }

    expect() {  # $1 = variant, $2 = expected exit code, $3 = description
        local dir="$TMP/$1"; make_fixture "$dir" "$1"
        KIRO_STEERING_ROOT="$dir" bash "$SELF" >/dev/null 2>&1
        local rc=$?
        if [[ $rc -eq $2 ]]; then printf '  ok     %s (exit %d)\n' "$3" "$rc"
        else printf '  FAIL   %s — expected exit %d, got %d\n' "$3" "$2" "$rc"; st_fail=1; fi
    }

    echo "Self-test: check-steering-allocation.sh"
    expect good     0 "correct tree passes"
    expect noglob   1 "orchestrator with no steering glob is rejected"
    expect halfglob 1 "orchestrator missing the home-absolute glob is rejected"
    expect always   1 "steering file with inclusion: always is rejected"
    expect manual   1 "steering file with inclusion: manual is rejected (never delivered)"
    expect subglob  1 "subagent declaring a steering glob is rejected"
    expect drift    1 "allocation drift is rejected"
    expect missing  1 "declared-but-absent steering file is rejected"
    expect oddprefix   1 "subagent on the wrong prefix for its tree is rejected"
    expect mixedprefix 1 "subagent mixing both prefixes is rejected"
    echo
    [[ $st_fail -eq 0 ]] && { echo "Self-test OK: 10/10"; exit 0; }
    echo "Self-test FAILED"; exit 1
fi

# ---------------------------------------------------------------- main check
ROOT="${KIRO_STEERING_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[[ -d "$ROOT/steering" && -d "$ROOT/agents" ]] || { echo "FAIL: no steering/ + agents/ under $ROOT"; exit 1; }
echo "Checking: $ROOT"

fail=0
note() { printf '  %-6s %s\n' "$1" "$2"; [[ "$1" == FAIL ]] && fail=1; return 0; }

# 1. No steering file may be globally auto-included.
always_seen=0
while IFS= read -r f; do
    if grep -qE '^inclusion:[[:space:]]*always' "$f"; then
        note FAIL "$(basename "$f"): inclusion: always — injected into every agent, per-agent lists are cosmetic"
        always_seen=1
    elif grep -qE '^inclusion:[[:space:]]*manual' "$f"; then
        note FAIL "$(basename "$f"): inclusion: manual — NEVER delivered, not even when named in resources:"
        always_seen=1
    elif grep -qE '^inclusion:' "$f"; then
        note FAIL "$(basename "$f"): unexpected inclusion: key — steering files must carry none"
        always_seen=1
    fi
done < <(find "$ROOT/steering" -name '*.md')
[[ $always_seen -eq 0 ]] && note ok "no steering file carries an inclusion: key (delivery works)"

# 2. The orchestrator MUST declare both globs; no other agent may declare any.
orchestrator=""
for f in "$ROOT"/agents/*.md; do
    n=$(basename "$f" .md)
    case "$n" in
        architect) orchestrator="$f" ;;
        *) grep -qF -- "/steering/**" "$f" &&
               note FAIL "$n: declares a steering glob; only the orchestrator should" ;;
    esac
done
if [[ -z "$orchestrator" ]]; then
    note FAIL "no orchestrator agent (architect.md) found under $ROOT/agents"
else
    on=$(basename "$orchestrator" .md)
    for g in "$PROJECT_GLOB" "$HOME_GLOB"; do
        if grep -qF -- "$g" "$orchestrator"; then
            note ok "$on: declares $g"
        else
            note FAIL "$on: missing required steering glob $g"
        fi
    done
fi

# 3. Declared steering targets must exist, use a consistent prefix, and match the published table.
python3 - "$ROOT" <<'PYEOF'
import sys,os,yaml
root=sys.argv[1]
EXPECTED={
 'coder':             {'delivery-workflow','minimalism','testing','doc-research','dependency-versions',
                       'virtual-environments','cli-execution','artifact-locations','documentation'},
 'ops':               {'delivery-workflow','minimalism','testing','doc-research','dependency-versions',
                       'virtual-environments','cli-execution','artifact-locations','documentation'},
 'reviewer':          {'delivery-workflow','testing','minimalism','cli-execution','artifact-locations',
                       'dependency-versions','doc-research','virtual-environments'},
 'security-reviewer': {'delivery-workflow','cli-execution','artifact-locations','dependency-versions'},
 'docs':              {'documentation','artifact-locations','cli-execution','delivery-workflow',
                       'dependency-versions'},
}
bad=0
prefixes={}   # agent -> set of prefixes used ('home' / 'project')
# Only .md files are agent profiles. `agents/` may also hold examples or notes (e.g.
# agent_config.json.example) — parsing those as frontmatter crashed the check.
for f in sorted(x for x in os.listdir(root+'/agents') if x.endswith('.md')):
    n=f[:-3]
    d=yaml.safe_load(open(f'{root}/agents/{f}').read().split('---',2)[1]) or {}
    got=set()
    for r in (d.get('resources') or []):
        if '/steering/' not in r:
            continue
        # Record the prefix even for globs — the orchestrator legitimately uses both.
        prefixes.setdefault(n,set()).add('home' if r.startswith('file://~/') else 'project')
        if '**' in r:
            continue
        fn=r.split('/steering/')[1]
        if not os.path.exists(f'{root}/steering/{fn}'):
            print(f'  FAIL   {n}: declares missing steering file {fn}'); bad=1
        got.add(fn[:-3])
    if n in EXPECTED:
        if got!=EXPECTED[n]:
            print(f'  FAIL   {n}: allocation drift'
                  f'\n           missing: {sorted(EXPECTED[n]-got) or "none"}'
                  f'\n           extra:   {sorted(got-EXPECTED[n]) or "none"}'); bad=1
        else:
            size=sum(os.path.getsize(f'{root}/steering/{x}.md') for x in got)
            print(f'  ok     {n}: {len(got)} files, {size:,} B')

# Prefix consistency. The existence check above resolves basenames under $ROOT, so it cannot tell
# `file://.kiro/steering/x.md` from `file://~/.kiro/steering/x.md` — a subagent left on the wrong
# prefix for its tree loads NOTHING and still reports ok. That actually shipped: two public-tree
# subagents kept the private tree's home-absolute prefix and this check certified them as correct.
# Every subagent in a tree must therefore agree on one prefix; only the orchestrator may use both.
subagent_prefixes={n:p for n,p in prefixes.items() if n in EXPECTED}
for n,p in sorted(subagent_prefixes.items()):
    if len(p)>1:
        print(f'  FAIL   {n}: mixes home-absolute and project-relative steering prefixes'); bad=1
used={next(iter(p)) for p in subagent_prefixes.values() if len(p)==1}
if len(used)>1:
    majority=max(used,key=lambda k:sum(1 for p in subagent_prefixes.values() if p=={k}))
    odd=sorted(n for n,p in subagent_prefixes.items() if p!={majority})
    print(f'  FAIL   subagents disagree on the steering prefix: most use {majority}-form, '
          f'but {", ".join(odd)} differ'
          f'\n           a subagent whose prefix does not match its install root loads NO steering'); bad=1
elif used:
    print(f'  ok     all {len(subagent_prefixes)} subagents use the {next(iter(used))}-form prefix')
sys.exit(bad)
PYEOF
[[ $? -ne 0 ]] && fail=1

echo
if [[ $fail -eq 0 ]]; then
    cat <<'EOM'
OK: static checks pass.

Runtime verification (NOT covered above — do this once after any change here):
  1. Start a session as a lean agent:  kiro-cli --v3 chat --agent security-reviewer
     The --v3 flag is REQUIRED: without it the markdown agents do not resolve at all
     ("no agent with name X found. Falling back to user specified default"), and any
     answer you get describes the fallback agent instead of the one you asked for.
  2. Ask it: "list every steering rule you can see, by filename"
  3. It must name exactly the files declared in its resources: block — not all nine.
If it names all nine, the engine is still auto-including them and the published byte
reductions are not real. Re-check for any `inclusion:` key and for a project-level
.kiro/steering/ shadowing the user-global one.
EOM
    exit 0
fi
echo "FAILED: see above."
exit 1

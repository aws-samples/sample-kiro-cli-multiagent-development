#!/usr/bin/env bash
# Runnable check for guard-config-writes.sh.
#
# The guard must block writes TO the enforcement surface while allowing reads and copies
# FROM it. That distinction is the whole design: a guard that blocks `rsync ~/.kiro/hooks/
# -> elsewhere` is a guard that gets disabled, and a guard that allows
# `sed -i ... permissions.yaml` is no guard at all.
#
# Residual honest: even with target resolution a determined adversary can bypass this
# guard via base64 -d | sh, eval of dynamically assembled paths, or other
# eval-equivalent constructs. The defensible claim is that the guard blocks idiomatic
# and injected-instruction forms, not that it is a security boundary.
#
# Usage: bash ~/.kiro/hooks/scripts/test-guard-config-writes.sh
# Exit 0 = all cases correct. Exit 1 = at least one wrong.

set -uo pipefail

GUARD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard-config-writes.sh"
[[ -f "$GUARD" ]] || { echo "FAIL: guard not found at $GUARD"; exit 1; }

pass=0; fail=0
# Home is derived at runtime, never hardcoded: this suite ships in a public sample, and an
# absolute path built from the author's home both leaked the username and made the
# MUST-BLOCK case fail on every reader's machine (the path is not inside their
# CONFIG_ROOTS, so the guard correctly allows it).
H="$HOME"

# probe_cwd <want> <cwd> <cmd> — exercises the event's cwd field, which every other case
# leaves at /tmp. The guard resolving relative targets against the wrong base was a total
# bypass.
probe_cwd() {
    local want="$1" wd="$2" cmd="$3" got
    printf '{"hook_event_name":"PreToolUse","cwd":%s,"tool_input":{"cwd":%s,"command":%s}}' \
        "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$wd")" \
        "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$wd")" \
        "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$cmd")" \
        | bash "$GUARD" >/dev/null 2>&1
    got=$?
    if [[ "$got" == "$want" ]]; then
        pass=$((pass+1)); printf '  ok    exit=%s  [cwd=%s] %s\n' "$got" "$wd" "$cmd"
    else
        fail=$((fail+1)); printf '  FAIL  exit=%s (want %s)  [cwd=%s] %s\n' "$got" "$want" "$wd" "$cmd"
    fi
}
probe() {
    local want="$1" cmd="$2" got
    printf '{"hook_event_name":"PreToolUse","cwd":"/tmp","tool_input":{"command":%s}}' \
        "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$cmd")" \
        | bash "$GUARD" >/dev/null 2>&1
    got=$?
    if [[ "$got" == "$want" ]]; then
        pass=$((pass+1)); printf '  ok    exit=%s  %s\n' "$got" "$cmd"
    else
        fail=$((fail+1)); printf '  FAIL  exit=%s (want %s)  %s\n' "$got" "$want" "$cmd"
    fi
}

echo "guard-config-writes.sh"
echo
echo "MUST BLOCK — writes targeting the enforcement surface (original cases):"
probe 2 "sed -i '' '/169.254.169.254/d' ~/.kiro/settings/permissions.yaml"
probe 2 "rm ~/.kiro/hooks/02-guard-secret-reads.json"
probe 2 "echo 'rules: []' > ~/.kiro/settings/permissions.yaml"
probe 2 "rtk run sed -i s/deny/allow/ ~/.kiro/settings/permissions.yaml"
probe 2 "cp /tmp/evil.yaml ~/.kiro/settings/permissions.yaml"
probe 2 "rsync -a /tmp/evil/ ~/.kiro/hooks/"
probe 2 "chmod 000 ~/.kiro/hooks/scripts/guard-secret-reads.sh"
probe 2 "rm ~/.kiro/hooks/scripts/guard-config-writes.sh"
probe 2 "cat /tmp/x.yaml > ~/.kiro/settings/permissions.yaml"
probe 2 "ls /tmp && rm ~/.kiro/hooks/00-guard-destructive-commands.json"

echo
echo "MUST BLOCK — W1(a): 2>/dev/null shifts the 'last' target:"
probe 2 "cp /tmp/evil.sh ~/.kiro/hooks/scripts/guard-secret-reads.sh 2>/dev/null"
probe 2 "rsync -a /tmp/evil/ ~/.kiro/hooks/ 2>/dev/null"
probe 2 "mv /tmp/evil.yaml ~/.kiro/settings/permissions.yaml >/dev/null"

echo
echo "MUST BLOCK — W1(b): glob and variable spellings of the config path:"
probe 2 "rm ~/.kiro/hook?/02-guard-secret-reads.json"
probe 2 "sed -i '' '/169.254/d' ~/.kiro/setting?/permission?.yaml"
probe 2 "chmod -R 000 ~/.kiro/hook?"
probe 2 "D=~/.kiro; rm \$D/hooks/02-guard-secret-reads.json"
probe 2 "echo 'rules: []' >| ~/.kiro/settings/permissions.yaml"

echo
echo "MUST BLOCK — W1(c): cd + relative path and xargs pipelines:"
probe 2 "cd ~/.kiro/hooks && rm 02-guard-secret-reads.json"
probe 2 "( cd ~/.kiro/hooks && rm 02-guard-secret-reads.json )"
probe 2 "cd ~/.kiro && rm -r hooks"
probe 2 "echo ~/.kiro/hooks/02-guard-secret-reads.json | xargs rm"
probe 2 "find ~/.kiro/hooks -name '*.json' -print0 | xargs -0 rm"
probe 2 "python3 -c \"p='$H/.kiro/settings/permissions.yaml'; open(p,'w').write('rules: []')\""

echo
echo "MUST BLOCK — cwd supplied by the tool, bare relative target (was a total bypass):"
probe_cwd 2 "$H/.kiro/hooks"   "rm 02-guard-secret-reads.json"
probe_cwd 2 "$H/.kiro/settings" "sed -i '' '/169.254/d' permissions.yaml"
probe_cwd 2 "$H/.kiro/hooks/scripts" "rm guard-secret-reads.sh"

echo
echo "MUST BLOCK — case variants (APFS resolves these to the real files):"
probe 2 "rm $H/.KIRO/hooks/02-guard-secret-reads.json"
probe 2 "rm $H/.kiro/Hooks/02-guard-secret-reads.json"
probe 2 "sed -i '' '/169.254/d' $H/.kiro/Settings/permissions.yaml"

echo
echo "MUST BLOCK — decoy one-liner must not hide the real one:"
probe 2 "python3 -c 'print(1)'; python3 -c \"open('$H/.kiro/settings/permissions.yaml','w')\""

echo
echo "MUST BLOCK — pipeline sinks other than rm:"
probe 2 "echo $H/.kiro/settings/permissions.yaml | xargs sed -i '' '/169.254/d'"
probe 2 "echo $H/.kiro/hooks/02-guard-secret-reads.json | xargs unlink"

echo
echo "MUST BLOCK — mutator verbs beyond rm:"
probe 2 "unlink $H/.kiro/hooks/02-guard-secret-reads.json"
probe 2 "patch $H/.kiro/settings/permissions.yaml /tmp/evil.diff"
probe 2 "tar xf /tmp/evil.tar -C $H/.kiro/hooks"
probe 2 "unzip -o /tmp/evil.zip -d $H/.kiro/hooks"
probe 2 "touch $H/.kiro/hooks/99-disable.json"
probe 2 "find $H/.kiro/hooks -name '*.json' -exec unlink {} \\;"
probe 2 "python3 -c \"import os; os.remove('$H/.kiro/hooks/02-guard-secret-reads.json')\""

echo
echo "MUST BLOCK — W1(d): find -delete:"
probe 2 "find ~/.kiro/hooks -name '*.json' -delete"

echo
echo "MUST BLOCK — W1(f): cp -t DEST (Linux --target-directory form):"
probe 2 "cp -t ~/.kiro/hooks/scripts /tmp/evil.sh"
probe 2 "cp --target-directory=~/.kiro/hooks/scripts /tmp/evil.sh"

echo
echo "MUST ALLOW — reads and copies FROM the config, and unrelated writes (original cases):"
probe 0 "cat ~/.kiro/settings/permissions.yaml"
probe 0 "grep -n rules ~/.kiro/settings/permissions.yaml"
probe 0 "bash -n ~/.kiro/hooks/scripts/guard-secret-reads.sh"
probe 0 "bash ~/.kiro/hooks/scripts/test-guard-secret-reads.sh"
probe 0 "ls ~/.kiro/hooks"
probe 0 "cp ~/.kiro/settings/permissions.yaml /tmp/backup.yaml"
probe 0 "rsync -a ~/.kiro/hooks/ /tmp/publicrepo/hooks/"
probe 0 "diff ~/.kiro/settings/permissions.yaml /tmp/other.yaml"
probe 0 "rm /tmp/scratch.txt"
probe 0 "echo hi > /tmp/notes.md"

echo
echo "MUST ALLOW — here-doc body mentions config paths as prose (not a write target):"
probe 0 "cat >> /tmp/notes.md << 'EOF'
This is a note about rm ~/.kiro/hooks/02-guard-secret-reads.json and
sed -i '' '/169.254.169.254/d' ~/.kiro/settings/permissions.yaml being blocked.
EOF"

echo
echo "MUST ALLOW — the documented private->public mirror workflow:"
# These regressed once: an earlier is_config_target() also matched on basename ==
# 'permissions.yaml' regardless of location, which blocked the mirror. The rule was
# redundant (effective-cwd tracking already catches a bare `permissions.yaml` after a
# `cd` into the config dir — see the MUST-BLOCK case above) and is gone. Keep these
# cases so it cannot come back.
probe 0 "cp $H/.kiro/settings/permissions.yaml /tmp/publicrepo/settings/permissions.yaml"
probe 0 "rsync -a ~/.kiro/settings/permissions.yaml /tmp/publicrepo/settings/permissions.yaml"
probe 0 "cp ~/.kiro/hooks/scripts/guard-secret-reads.sh /tmp/publicrepo/hooks/scripts/guard-secret-reads.sh"
probe 0 "echo 'rules: []' > /tmp/someproject/permissions.yaml"
# A BARE `permissions.yaml` with a mutator IS blocked, even outside the config dir. This
# is the deliberate cost of the cwd-independent backstop: the guard cannot know which
# directory a tool-supplied cwd points at, so a slash-free config filename plus a mutator
# is treated as a target. An unrelated project pays one prompt; the alternative is a total
# bypass. Path-qualified writes to another project's permissions.yaml stay allowed (above).
probe_cwd 2 "/tmp/someproject" "echo 'rules: []' > permissions.yaml"

echo
if [[ $fail -eq 0 ]]; then echo "OK: $pass/$pass cases correct."; exit 0; fi
echo "FAILED: $fail of $((pass+fail)) cases wrong."; exit 1

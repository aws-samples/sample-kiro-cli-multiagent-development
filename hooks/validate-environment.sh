#!/bin/bash
# Hook: Validate required tools are installed and print versions.
# Trigger: agentSpawn
# Exits non-zero only if critical tools (python3, git) are missing.

set -uo pipefail

# Consume stdin (hook event)
cat >/dev/null

MISSING_CRITICAL=0

check_tool() {
    local name="$1"
    local cmd="$2"
    local critical="${3:-false}"
    local version
    if version=$($cmd 2>&1 | head -1); then
        echo "[env] $name: $version"
    else
        echo "[env] $name: [MISSING]"
        [ "$critical" = "true" ] && MISSING_CRITICAL=1
    fi
}

check_tool "python3" "python3 --version" "true"
check_tool "git" "git --version" "true"
check_tool "node" "node --version" "false"
check_tool "aws" "aws --version" "false"
check_tool "docker" "docker --version" "false"
check_tool "cargo" "cargo --version" "false"

exit $MISSING_CRITICAL

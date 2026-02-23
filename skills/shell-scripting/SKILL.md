---
name: shell-scripting
description: Bash and Zsh scripting patterns with built-in logging and non-interactive execution. Use when writing automation scripts, CLI tools, or system administration tasks.
---

# Shell Scripting

## Script Template

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="${LOG_FILE:-/tmp/${SCRIPT_NAME%.*}.log}"

log() { printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" | tee -a "$LOG_FILE"; }
info() { log "INFO" "$1"; }
warn() { log "WARN" "$1"; }
error() { log "ERROR" "$1" >&2; }
die() { error "$1"; exit 1; }

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME <required_arg> [optional_arg]
  -h, --help     Show this help
  -y, --yes      Skip confirmations (default: true)
  -v, --verbose  Enable debug output
EOF
    exit 0
}

# Defaults: non-interactive
YES=true
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        -y|--yes) YES=true; shift ;;
        -v|--verbose) VERBOSE=true; set -x; shift ;;
        --) shift; break ;;
        -*) die "Unknown option: $1" ;;
        *) break ;;
    esac
done

[[ $# -lt 1 ]] && die "Missing required argument. Use -h for help."

ARG1="$1"
ARG2="${2:-default_value}"

main() {
    info "Starting: $ARG1"
    # Your logic here
    info "Completed successfully"
}

main "$@"
```

## Essential Options

```bash
set -e          # Exit on error
set -u          # Error on undefined variables
set -o pipefail # Catch pipe failures
set -x          # Debug mode (print commands)
```

## Non-Interactive Patterns

```bash
# Auto-confirm dangerous commands
rm -rf "$DIR"  # No -i flag

# Provide defaults instead of prompting
RESPONSE="${RESPONSE:-yes}"

# Use heredoc for stdin
mysql -u root <<< "SELECT 1;"

# Timeout commands that might hang
timeout 30 curl -s "$URL" || die "Request timed out"

# Skip interactive pagers
git --no-pager log -10
aws ec2 describe-instances --no-cli-pager
```

## Zsh Compatibility

```zsh
# Zsh-specific: extended globbing
setopt extended_glob
rm -f **/*.tmp(N)  # (N) = nullglob, no error if no match

# Array handling (works in both)
arr=(one two three)
for item in "${arr[@]}"; do echo "$item"; done

# Zsh associative arrays
typeset -A map
map[key]=value
```

## Common Patterns

```bash
# Check command exists
command -v docker &>/dev/null || die "docker required"

# Cleanup on exit
cleanup() { [[ -f "$TMPFILE" ]] && rm -f "$TMPFILE"; }
trap cleanup EXIT
TMPFILE=$(mktemp)

# Retry with backoff
retry() {
    local n=0 max=3 delay=2
    while ! "$@"; do
        ((n++)) && ((n >= max)) && return 1
        info "Retry $n/$max in ${delay}s..."
        sleep $delay
        ((delay *= 2))
    done
}

# Parallel execution
parallel_run() {
    local pids=()
    for cmd in "$@"; do
        eval "$cmd" & pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid" || return 1; done
}
```

## String Operations

```bash
${var:0:5}      # First 5 chars
${var: -3}      # Last 3 chars
${var/old/new}  # Replace first
${var//old/new} # Replace all
${var#prefix}   # Remove prefix
${var%suffix}   # Remove suffix
${var:-default} # Default if unset
${var:?error}   # Error if unset
```

## Testing

```bash
[[ -f "$file" ]]    # File exists
[[ -d "$dir" ]]     # Directory exists
[[ -z "$var" ]]     # Variable empty
[[ -n "$var" ]]     # Variable not empty
[[ "$a" == "$b" ]]  # String equality
[[ "$a" -eq "$b" ]] # Numeric equality
[[ -t 0 ]]          # stdin is terminal (interactive)
```

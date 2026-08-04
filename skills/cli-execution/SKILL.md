---
name: cli-execution
description: CLI execution best practices covering RTK token compression, AWS discover-then-execute patterns, output control, and bash/zsh scripting with logging. Use when running CLI commands, querying AWS resources, writing automation scripts, or working with shell tooling.
---

# CLI Execution

## RTK — Token Compression

Prefix read-heavy, side-effect-free commands with `rtk` to compress their output 60–90% before it
enters context:

```bash
rtk cargo test
rtk git log
rtk git status
rtk npm run build
rtk pytest
rtk grep -r foo .
rtk ls
rtk tree
rtk diff
```

**Never prefix mutating or destructive commands with `rtk`** (`git push`, `git commit`, `rm`,
`npm install`, `npm publish`, deploys, `terraform apply`, `kubectl apply/delete`). Run those as
normal commands so they pass through the destructive-command guard hook unaltered.

A `rtk-compress` hook auto-compresses read-only, rtk-supported commands even if the prefix is
forgotten. Mutating and unsupported commands run normally regardless.

## AWS — Discover Then Execute

There is no built-in AWS tool. Work with AWS in two steps:

1. **Discover** — use the AWS Knowledge MCP server to find the right service/API/CLI command and
   read the relevant documentation (parameters, ARNs, required IAM actions).
2. **Execute** — run the actual `aws` CLI command in the shell. Read-only calls
   (`describe-*`, `list-*`, `get-*`, `s3 ls`) are auto-compressed by RTK; write/mutating calls run
   normally and prompt per `permissions.yaml`.

Prefer least-privilege and verify parameters/permissions against the MCP docs before executing.

### Pagination Control

Always use `--no-cli-pager` for complete results in a single response:

```bash
# Complete results — no truncation, no interactive pager
aws ec2 describe-instances --no-cli-pager
aws s3api list-objects-v2 --bucket my-bucket --no-cli-pager
aws iam list-users --no-cli-pager
```

Only omit `--no-cli-pager` when the user explicitly requests paginated output or asks for "first N
results".

### Query and Filtering

Combine `--no-cli-pager` with `--query` for efficient data retrieval:

```bash
# Running instances only
aws ec2 describe-instances --no-cli-pager \
  --query 'Reservations[].Instances[?State.Name==`running`].[InstanceId,InstanceType]'

# Large S3 objects
aws s3api list-objects-v2 --bucket my-bucket --no-cli-pager \
  --query 'Contents[?Size>`1000000`].[Key,Size]'

# Specific fields as table
aws ec2 describe-instances --no-cli-pager \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType]' \
  --output table
```

### Output Formats

```bash
--output json   # Default, full detail
--output table  # Human-readable
--output text   # Tab-separated, good for scripting
--output yaml   # YAML format
```

### Common AWS Patterns

```bash
# Get account ID
aws sts get-caller-identity --query 'Account' --output text --no-cli-pager

# List all regions
aws ec2 describe-regions --query 'Regions[].RegionName' --output text --no-cli-pager

# Wait for resource
aws ec2 wait instance-running --instance-ids i-1234567890abcdef0

# Dry run (check permissions)
aws ec2 run-instances --dry-run --image-id ami-12345 --instance-type t3.micro
```

## Shell Scripting

### Script Template

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

### Essential Options

```bash
set -e          # Exit on error
set -u          # Error on undefined variables
set -o pipefail # Catch pipe failures
set -x          # Debug mode (print commands)
```

### Non-Interactive Patterns

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

### Zsh Compatibility

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

### Common Patterns

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

### String Operations

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

### Testing Conditions

```bash
[[ -f "$file" ]]    # File exists
[[ -d "$dir" ]]     # Directory exists
[[ -z "$var" ]]     # Variable empty
[[ -n "$var" ]]     # Variable not empty
[[ "$a" == "$b" ]]  # String equality
[[ "$a" -eq "$b" ]] # Numeric equality
[[ -t 0 ]]          # stdin is terminal (interactive)
```

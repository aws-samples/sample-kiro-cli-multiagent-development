#!/bin/bash
# Hook: Block concrete-path reads of known secret files (SSH keys, cloud creds, etc.).
# Trigger: PreToolUse on read_file / read_files
# Exit 0 = allow, Exit 2 = block (returns STDERR to LLM)
#
# This restores the protection that the `fs_read: deny` block in permissions.yaml
# used to provide, WITHOUT the side effect that blanket-denied the scan tools
# (grep_search, file_search, list_directory). Those tools present a pattern or
# directory scope the policy engine cannot prove disjoint from the deny globs, so
# it failed closed and denied them. This hook only inspects concrete resolved
# paths on read_file/read_files, leaving pattern-based scans untouched.

set -euo pipefail

EVENT=$(cat)

_HOOK_EVENT="$EVENT" python3 << 'PYEOF'
import json, sys, os, fnmatch

# Secret files that must never be read by concrete path. Mirrors the old
# fs_read deny block. Patterns ending in /** match anything under that dir.
SECRET_PATTERNS = [
    "~/.ssh/**",
    "~/.aws/credentials",
    "~/.aws/config",
    "~/.aws/sso/cache/**",
    "~/.config/gcloud/**",
    "~/.config/gh/hosts.yml",
    "~/.kube/config",
    "~/.docker/config.json",
    "~/.netrc",
    "~/.npmrc",
    "~/.pypirc",
    "~/.git-credentials",
    "~/.gnupg/**",
]

# Secrets identified by name or extension ANYWHERE on disk, not just in $HOME.
# These cannot be expressed in permissions.yaml: a deny glob on fs_read makes
# grep_search and file_search fail closed, because the engine cannot prove a
# pattern scope disjoint from the deny globs. Re-verified 2026-07-24 — still
# reproduces on v3. See specs/2026-07-24-kiro-config-overhaul/decisions.md.
# Matched against the resolved path's BASENAME, case-folded (see below).
SECRET_BASENAME_PATTERNS = [
    "*.pem",
    "*.key",
    "*.p12",
    "*.pfx",
    "*.keystore",
    "*.jks",
    "*.ovpn",
    "*.kdbx",
    "id_rsa",
    "id_dsa",
    "id_ecdsa",
    "id_ed25519",
    ".env",
    ".env.*",
    ".envrc",
    ".netrc",
    ".pgpass",
    ".git-credentials",
    "credentials",
    "credentials.json",
    "service-account*.json",
]

# Templates and examples are not secrets — they exist to be read. Compared
# case-folded, like everything else here.
BASENAME_ALLOWLIST_SUFFIXES = (
    ".example",
    ".sample",
    ".template",
    ".dist",
    ".defaults",
)

try:
    event = json.loads(os.environ['_HOOK_EVENT'])
except (KeyError, json.JSONDecodeError) as e:
    # Fail open on malformed input: the hook input comes from the Kiro engine,
    # not an attacker, and this guard only ADDS protection. Breaking every read
    # on a parse error would be worse than the miss. Exit 1 = warning, proceed.
    print(f"guard-secret-reads: could not parse event: {e}", file=sys.stderr)
    sys.exit(1)

cwd = event.get('cwd') or os.getcwd()
inp = event.get('tool_input') or {}

def collect_paths(tool_input):
    paths = []
    if not isinstance(tool_input, dict):
        return paths
    p = tool_input.get('path')
    if isinstance(p, str) and p:
        paths.append(p)
    ps = tool_input.get('paths')
    if isinstance(ps, list):
        paths.extend([x for x in ps if isinstance(x, str) and x])
    return paths

def resolve(path):
    path = os.path.expanduser(path)
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    path = os.path.normpath(path)
    try:
        return os.path.realpath(path)
    except OSError:
        return path

def matches_secret(resolved):
    # ALL comparisons are case-folded. macOS (APFS) and Windows are
    # case-INSENSITIVE by default, so `~/.SSH/ID_RSA` and `key.PEM` reach the
    # same bytes as their lowercase spellings. A case-sensitive guard on a
    # case-insensitive filesystem is bypassed by changing one character of
    # case, which defeats the whole control. Folding costs nothing and the
    # only false-positive risk is on a case-sensitive volume where two files
    # differ solely by case — refusing to read a secret-shaped name there is
    # the safe direction.
    resolved_l = resolved.lower()

    for pat in SECRET_PATTERNS:
        expanded = os.path.expanduser(pat)
        if expanded.endswith('/**'):
            base = os.path.normpath(expanded[:-3])
            # Match either the literal base or its symlink-resolved target,
            # so a symlink into ~/.ssh can't slip a key read past the guard.
            for b in {base, (os.path.realpath(base) if os.path.exists(base) else base)}:
                b_l = b.lower()
                if resolved_l == b_l or resolved_l.startswith(b_l + os.sep):
                    return pat
        else:
            target = os.path.normpath(expanded)
            if resolved_l == target.lower():
                return pat
            try:
                if os.path.exists(target) and os.path.realpath(target).lower() == resolved_l:
                    return pat
            except OSError:
                pass

    # Name/extension-based match, anywhere on disk. Templates and examples are
    # explicitly exempt — they are meant to be read.
    basename = os.path.basename(resolved_l)
    if not basename.endswith(BASENAME_ALLOWLIST_SUFFIXES):
        for pat in SECRET_BASENAME_PATTERNS:
            if fnmatch.fnmatch(basename, pat):
                return pat
    return None

for candidate in collect_paths(inp):
    resolved = resolve(candidate)
    hit = matches_secret(resolved)
    if hit:
        print(f"BLOCKED: read of secret file '{candidate}'", file=sys.stderr)
        print(f"Resolves to: {resolved} (matches deny rule '{hit}')", file=sys.stderr)
        print("Reading credential/secret files is not permitted. If the user "
              "explicitly needs a value from this file, ask them to provide it "
              "directly rather than reading the file.", file=sys.stderr)
        sys.exit(2)

sys.exit(0)
PYEOF

exit $?

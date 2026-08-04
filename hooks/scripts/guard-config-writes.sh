#!/bin/bash
# Hook: require confirmation before a SHELL command modifies the enforcement surface.
# Trigger: PreToolUse on shell / execute_bash
# Exit 0 = allow, Exit 2 = block (STDERR returned to the LLM)
#
# Why this exists. Every filesystem control in this config is enforced against the
# fs_* tool family only:
#   - Kiro's hardcoded scope ("~/.kiro/settings/ ALWAYS DENIED", "~/.kiro/hooks/** ALWAYS ASKS")
#     binds fs_write.
#   - permissions.yaml's own `fs_write: ask` on ~/.kiro/** binds fs_write.
#   - guard-secret-reads.sh matches read_file|read_files.
# `shell: allow` is an unguarded equivalent for all of them. Verified 2026-07-24:
# `printf 'probe' > ~/.kiro/settings/.secprobe` succeeded with NO prompt, despite the
# documented "ALWAYS DENIED". And permissions.yaml is HOT-RELOADED, so a one-line
# `sed -i` disabling the SSRF denies, the rm -rf denies, or the secret-read guard takes
# effect immediately and persists user-global into every future session.
#
# Threat: prompt-injected content instructs one shell redirect and the whole permission
# layer is gone with no human in the loop.
#
# This guard is deliberately NARROW: it fires only when a command's resolved write
# targets land inside the config roots. Read-only inspection (cat/grep/bash -n over
# hooks/scripts) is untouched, so it does not hinder normal work — including work on
# this config. It also covers its own directory, so disabling it requires confirmation.
#
# Residual honest: even after target resolution a determined adversary can construct a
# spelling this parser will miss — base64 -d | sh, dynamically assembled paths via eval,
# heredocs used as executable code. The defensible claim is that the guard stops
# idiomatic and injected-instruction forms (cd into directory then rm, 2>/dev/null
# appended to cp, python3 -c one-liners, find -delete, xargs pipelines), not that it is
# a security boundary. Pair it with the engine-enforced `shell: ask` rule in
# permissions.yaml as a second layer; note that rule shares a literal-spelling weakness
# and so is belt, not braces.

set -euo pipefail

EVENT=$(cat)

_HOOK_EVENT="$EVENT" python3 << 'PYEOF'
import json, os, re, sys, glob as glob_module

# ---------------------------------------------------------------------------
# CONFIG_ROOTS: resolved once at startup.
# ---------------------------------------------------------------------------
CONFIG_ROOTS = {
    os.path.realpath(os.path.expanduser(p))
    for p in ('~/.kiro/settings', '~/.kiro/hooks')
}

# Is this filesystem case-insensitive? Probed once, not hardcoded per-platform: macOS
# APFS and Windows are case-insensitive by default, Linux ext4 is not, and the published
# sample runs on all three. Folding case on a case-sensitive volume would create false
# positives on genuinely distinct directories.
def _probe_case_insensitive():
    for root in CONFIG_ROOTS:
        try:
            alt = root.upper()
            if alt != root and os.path.exists(alt) and os.path.samefile(alt, root):
                return True
        except OSError:
            continue
    return False

FS_CASE_INSENSITIVE = _probe_case_insensitive()

# Basenames unique to the enforcement surface. Used ONLY for tokens that are relative
# and contain no '/', i.e. a bare filename acted on inside an unknown working directory.
# This is the cwd-independent backstop: execute_bash can supply its own `cwd`, which the
# hook event does not necessarily report, so `rm 02-guard-secret-reads.json` run inside
# ~/.kiro/hooks resolves against the wrong base and would otherwise pass. Scoped to
# slash-free tokens so it cannot affect the private->public mirror, whose operands are
# always absolute.
RELATIVE_SENTINELS = {'permissions.yaml'}
for _root in CONFIG_ROOTS:
    try:
        for _dirpath, _dirnames, _filenames in os.walk(_root):
            for _f in _filenames:
                if not _f.startswith('.'):
                    RELATIVE_SENTINELS.add(_f)
    except OSError:
        pass

# ---------------------------------------------------------------------------
# MUTATORS: (regex, label, position)
#
# position values:
#   'any'      — every token (plus quoted path literals) in the segment is a candidate
#   'last'     — only the final non-flag token is the destination
#   'redirect' — the path following >, >>, or >| is the target
#   'find'     — non-flag path arguments before the first -option are the search roots
# ---------------------------------------------------------------------------
MUTATORS = [
    # Redirects first — position 'redirect' uses its own extractor.
    (r'>\|?>?\s*([^|&\s]+)', 'shell redirect (> >> >|)', 'redirect'),
    (r'\btee\b', 'tee', 'any'),
    (r'\bsed\b[^|;]*-i', 'sed -i', 'any'),
    (r'\bperl\b[^|;]*-i', 'perl -i', 'any'),
    (r'\brm\b', 'rm', 'any'),
    (r'\btruncate\b', 'truncate', 'any'),
    (r'\bchmod\b', 'chmod', 'any'),
    (r'\bchown\b', 'chown', 'any'),
    (r'\bdd\b[^|;]*\bof=', 'dd of=', 'any'),
    (r"open\([^)]*['\"][wa]", "python open(...,'w')", 'any'),
    (r'\bwrite_text\b', 'pathlib write_text', 'any'),
    (r'\byq\b[^|;]*-i', 'yq -i', 'any'),
    (r'\bgit\s+checkout\b', 'git checkout (can overwrite)', 'any'),
    (r'\bgit\s+restore\b', 'git restore (can overwrite)', 'any'),
    (r'\bunlink\b', 'unlink', 'any'),
    (r'\bshred\b', 'shred', 'any'),
    (r'\btouch\b', 'touch', 'any'),
    (r'\bpatch\b', 'patch', 'any'),
    (r'\bgit\s+apply\b', 'git apply', 'any'),
    (r'\bex\b\s+-\S*c', 'ex -c', 'any'),
    (r'\bawk\b[^|;]*-i\s+inplace', 'awk -i inplace', 'any'),
    (r'\bos\.(?:remove|unlink|rename|replace)\b', 'python os.remove/unlink/rename', 'any'),
    (r'\bshutil\.rmtree\b', 'python shutil.rmtree', 'any'),
    (r'\.unlink\(', 'pathlib unlink', 'any'),
    (r'\bwriteFileSync\b', 'node writeFileSync', 'any'),
    (r'\bunlinkSync\b', 'node unlinkSync', 'any'),
    (r'\bunlink\s+["\']', 'perl unlink', 'any'),
    (r'\bg(?:sed|rm|cp|mv)\b', 'GNU coreutils g-prefixed', 'any'),
    # 'last': destination is the final non-flag argument, UNLESS -t/--target-directory
    # is present (handled separately in check_segment).
    (r'\bcp\b', 'cp', 'last'),
    (r'\bmv\b', 'mv', 'last'),
    (r'\brsync\b', 'rsync', 'last'),
    (r'\bln\b', 'ln', 'last'),
    (r'\binstall\b', 'install', 'last'),
    # Extraction into a directory: -C (tar) / -d (unzip) names the destination.
    (r'\btar\b[^|;]*\s-\S*C\s', 'tar -C', 'extract'),
    (r'\bunzip\b[^|;]*\s-d\s', 'unzip -d', 'extract'),
    # find -delete: the non-flag path arguments before options are the roots.
    (r'\bfind\b[^|;]*-delete\b', 'find -delete', 'find'),
    (r'\bfind\b[^|;]*-exec\b[^|;]*\b(?:rm|unlink|shred|truncate)\b', 'find -exec remover', 'find'),
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def strip_quotes(token: str) -> str:
    """Remove surrounding single or double quotes from a token."""
    if len(token) >= 2 and token[0] == token[-1] and token[0] in ('"', "'"):
        return token[1:-1]
    return token


def resolve_token(token: str, cwd: str, env: dict) -> list:
    """
    Resolve a shell token to one or more real paths.

    Steps:
      1. Strip surrounding quotes.
      2. Drop redirection/fd tokens matching ^[0-9]*[<>&].
      3. Drop pure flag tokens (start with -), except --target-directory=.
      4. Substitute $HOME and ~ with the real home directory.
      5. Substitute $VAR / ${VAR} from env (caller-collected assignments).
      6. Join relative paths against cwd.
      7. glob.glob() to expand wildcards; realpath each result.
      8. realpath on the unexpanded form too (handles symlinks and ..).

    Returns a (possibly empty) list of resolved absolute paths.
    """
    token = strip_quotes(token)

    # Drop fd/redirection meta-tokens: 2>, &1, <, >/dev/null, etc.
    if re.match(r'^[0-9]*[<>&]', token):
        return []

    # Drop pure flag tokens (but not --target-directory=PATH).
    if token.startswith('-') and not token.startswith('--target-directory='):
        return []

    # Expand --target-directory=PATH
    if token.startswith('--target-directory='):
        token = token[len('--target-directory='):]

    home = os.path.expanduser('~')

    # Substitute $HOME / ${HOME}
    token = token.replace('$HOME', home).replace('${HOME}', home)

    # Expand leading ~ / ~/
    if token == '~':
        token = home
    elif token.startswith('~/'):
        token = home + token[1:]

    # Substitute other $VAR / ${VAR} from collected assignments.
    for var, val in env.items():
        token = token.replace(f'${{{var}}}', val)
        token = token.replace(f'${var}', val)

    if not token:
        return []

    # Resolve relative paths against cwd.
    if not os.path.isabs(token):
        token = os.path.join(cwd, token)

    # Expand globs.
    expanded = glob_module.glob(token)
    if expanded:
        return [os.path.realpath(p) for p in expanded]

    # No glob matches (path may not exist yet — still check it).
    return [os.path.realpath(token)]


def is_config_target(resolved: str) -> bool:
    """
    Return True if resolved is inside (or IS) one of the CONFIG_ROOTS, or if the
    realpath's parent is a CONFIG_ROOT (catches symlink indirection).

    Comparison is case-folded when the filesystem is case-insensitive. macOS/APFS
    resolves ~/.KIRO/hooks and ~/.kiro/Hooks to the same real directory, but
    os.path.realpath() does NOT canonicalise case, so a byte-for-byte compare let one
    capital letter bypass the guard entirely. Gated on an actual probe rather than
    hardcoded to darwin, because the published sample also runs on Linux where ~/.KIRO
    is a genuinely different directory and folding would create false positives.

    Deliberately NOT matched on basename. An earlier version blocked any path whose
    basename was `permissions.yaml` regardless of location, which broke the documented
    private->public mirror and any unrelated project's own permissions.yaml. The bare
    relative filename case it was reaching for is handled by RELATIVE_SENTINELS below,
    which is scoped to tokens containing no '/' and therefore cannot affect the mirror
    (both of its operands are absolute).
    """
    def fold(p):
        # NOT os.path.normcase — that only lowercases on Windows and is a no-op on
        # POSIX, so it silently did nothing on the macOS volume this guard protects.
        return p.lower() if FS_CASE_INSENSITIVE else p

    r = fold(resolved)
    for root in CONFIG_ROOTS:
        rt = fold(root)
        if r == rt or r.startswith(rt + os.sep):
            return True
        if fold(os.path.dirname(resolved)) == rt:
            return True
    return False


def collect_assignments(text: str) -> dict:
    """
    Collect VAR=value assignments from the command text.
    Handles:  D=~/.kiro  P=$HOME/.kiro/settings  etc.
    Stops at shell separator characters so D=~/.kiro; does not include the ;.
    Does not try to evaluate arithmetic or command substitution.
    """
    env = {}
    home = os.path.expanduser('~')
    # Stop value at whitespace or shell operators (; & | ( ))
    for m in re.finditer(r'\b([A-Za-z_][A-Za-z0-9_]*)=([^\s;&|()]+)', text):
        var, val = m.group(1), m.group(2)
        val = strip_quotes(val)
        val = val.replace('$HOME', home).replace('${HOME}', home)
        if val == '~':
            val = home
        elif val.startswith('~/'):
            val = home + val[1:]
        env[var] = val
    return env


def extract_interpreter_oneliners(text: str) -> list:
    """
    Return the quoted body of EVERY interpreter one-liner in the text, so semicolons
    inside a quoted program cannot split path from mutator.

    Uses finditer, not search: an earlier version returned only the first match while the
    caller stripped ALL matches from the command, so a decoy one-liner
    (`python3 -c 'print(1)'; python3 -c "open('...','w')"`) deleted the real one from
    analysis entirely.
    """
    return [m.group(2) for m in re.finditer(
        r'\b(?:python3?|perl|ruby|sh|bash|node)\s+-(?:c|e|-eval)\s+(["\'])(.*?)\1',
        text,
        re.DOTALL,
    )]


def has_pipeline_mutator(segments: list) -> bool:
    """
    True if any downstream pipeline stage is a sink that writes to paths read from stdin.

    Any `xargs` counts, not just `xargs rm` — the earlier enumeration missed
    `xargs sed -i`, `xargs unlink`, and every other verb xargs can drive.
    """
    for seg in segments[1:]:
        if re.search(r'\bxargs\b', seg):
            return True
        if re.search(r'\b(?:tee|sponge)\b', seg):
            return True
    return False


def extract_quoted_paths(text: str) -> list:
    """
    Extract path-like strings from single- or double-quoted literals in text.
    Used to find paths assigned to variables inside interpreter one-liners,
    e.g. p='/Users/.../.kiro/settings/permissions.yaml'.
    Only returns strings that contain at least one / (i.e. look like paths).
    """
    return re.findall(r"""['"]((?:[^'"]*\/[^'"]*)+)['"]""", text)


def check_segment(segment: str, cwd: str, env: dict) -> tuple:
    """
    Check a single command segment for writes targeting a CONFIG_ROOT.

    Returns (blocked: bool, label: str, hit_token: str).
    """
    for pattern, label, position in MUTATORS:
        m = re.search(pattern, segment)
        if not m:
            continue

        if position == 'redirect':
            # Extract all redirect targets (> >> >|).
            raw_targets = re.findall(r'>\|?>?\s*([^|&\s]+)', segment)
            candidates = raw_targets
        elif position == 'find':
            # For find -delete: check the non-flag tokens before the first -option.
            toks = segment.split()
            candidates = []
            for t in toks[1:]:  # skip 'find' itself
                if t.startswith('-'):
                    break
                candidates.append(t)
        elif position == 'extract':
            # tar -C DEST / unzip -d DEST: the flag's argument is the destination dir.
            m2 = re.search(r'\s-\S*C\s+(\S+)', segment) or re.search(r'\s-d\s+(\S+)', segment)
            candidates = [m2.group(1)] if m2 else []
        elif position == 'last':
            # Check for -t / --target-directory first.
            t_match = re.search(r'\s-t\s+(\S+)', segment)
            td_match = re.search(r'--target-directory=(\S+)', segment)
            if t_match:
                candidates = [t_match.group(1)]
            elif td_match:
                candidates = [td_match.group(1)]
            else:
                # Destination is the last non-flag, non-redirect token.
                toks = [
                    t for t in segment.split()
                    if not t.startswith('-')
                    and not re.match(r'^[0-9]*[<>&]', t)
                ]
                candidates = toks[-1:] if toks else []
        else:  # 'any'
            # Regular non-flag tokens.
            candidates = [
                t for t in segment.split()
                if not t.startswith('-')
                and not re.match(r'^[0-9]*[<>&]', t)
            ]
            # Also include quoted path literals (for interpreter one-liners where
            # the path is assigned to a variable: p='/.../.kiro/settings/...')
            candidates.extend(extract_quoted_paths(segment))

        for raw in candidates:
            # cwd-independent backstop: a bare filename (no '/') that matches a name
            # unique to the enforcement surface. Catches the case where execute_bash
            # supplies its own `cwd` that the hook event does not report, so relative
            # targets cannot be resolved correctly.
            bare = strip_quotes(raw)
            if '/' not in bare and bare in RELATIVE_SENTINELS:
                return True, label, bare
            for resolved in resolve_token(raw, cwd, env):
                if is_config_target(resolved):
                    return True, label, raw

    return False, '', ''


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try:
    event = json.loads(os.environ['_HOOK_EVENT'])
except (KeyError, json.JSONDecodeError) as e:
    print(f"guard-config-writes: could not parse event: {e}", file=sys.stderr)
    sys.exit(1)

cmd = (event.get('tool_input') or {}).get('command') or ''
if not cmd:
    sys.exit(0)

# Strip rtk wrappers so `rtk run sed -i ... permissions.yaml` cannot hide the mutation.
stripped = re.sub(r'^\s*rtk\s+(run\s+|proxy\s+)?', '', cmd)

# Prefer the working directory the TOOL was given over the event's project-level cwd.
# execute_bash accepts its own `cwd`, and the shell honours it; the event's top-level
# `cwd` is documented as the project directory. Reading only the latter meant every
# relative-path mutation run inside a config directory resolved against the wrong base
# and passed. The field name on tool_input is unverified, hence the RELATIVE_SENTINELS
# backstop in check_segment which does not depend on knowing the cwd at all.
_ti = event.get('tool_input') or {}
event_cwd = _ti.get('cwd') or event.get('cwd') or os.getcwd()

# Collect VAR=value assignments from the whole command — needed for cross-segment
# variable expansion (D=~/.kiro; rm $D/hooks/…).
env = collect_assignments(stripped)

# ---------------------------------------------------------------------------
# Step 1: Extract interpreter one-liners and treat them as indivisible segments.
# This prevents a semicolon inside python3 -c "…" from splitting path from mutator.
# ---------------------------------------------------------------------------
oneliner_segments = extract_interpreter_oneliners(stripped)

# Remove interpreter one-liners from the command before segment-splitting.
split_base = stripped
if oneliner_segments:
    split_base = re.sub(
        r'\b(?:python3?|perl|ruby|sh|bash|node)\s+-(?:c|e|-eval)\s+(["\'])(.*?)\1',
        '',
        split_base,
        flags=re.DOTALL,
    )

# ---------------------------------------------------------------------------
# Step 2: Split into segments on shell separators (; && || & newline).
# Heredoc detection: once << MARKER is seen, skip lines until MARKER is found
# (the heredoc body is data, not commands — it must not be scanned for targets).
# Pipeline stages are kept together when any downstream stage is a sink mutator.
# Split on | only when NOT immediately preceded by > (to avoid splitting >|).
# ---------------------------------------------------------------------------
raw_line_segs = re.split(r'[;&]+|\n', split_base)

# Track heredoc state across line segments.
heredoc_marker = None
line_segs_no_heredoc = []
for seg in raw_line_segs:
    if heredoc_marker is not None:
        # Inside a heredoc body — skip this segment entirely.
        if seg.strip() == heredoc_marker:
            heredoc_marker = None  # end of heredoc
        continue
    # Detect start of a heredoc in this segment.
    hm = re.search(r'<<-?\s*[\'"]?(\w+)[\'"]?', seg)
    if hm:
        heredoc_marker = hm.group(1)
    line_segs_no_heredoc.append(seg)

all_segments = []
for raw_seg in line_segs_no_heredoc:
    # Split on | only when not preceded by > (so >| is not split).
    pipe_stages = re.split(r'(?<!>)\|+', raw_seg)
    if len(pipe_stages) > 1 and has_pipeline_mutator(pipe_stages):
        # Treat the whole pipeline as one segment — the path tokens in the first
        # stage are targets of the downstream sink mutator (xargs rm, tee).
        all_segments.append(raw_seg)
    else:
        all_segments.extend(pipe_stages)

# Add every interpreter one-liner body as its own indivisible segment.
all_segments.extend(oneliner_segments)

# ---------------------------------------------------------------------------
# Step 3: Walk segments, tracking effective cwd across cd / pushd.
# ---------------------------------------------------------------------------
cwd = event_cwd

for segment in all_segments:
    # Strip leading subshell parens and whitespace.
    segment = segment.strip().lstrip('(').strip()
    if not segment:
        continue

    # Track cwd changes so relative rm / write targets resolve correctly.
    cd_match = re.match(r'(?:cd|pushd)\s+(\S+)', segment)
    if cd_match:
        new_dir = strip_quotes(cd_match.group(1))
        home = os.path.expanduser('~')
        new_dir = new_dir.replace('$HOME', home).replace('${HOME}', home)
        if new_dir == '~':
            new_dir = home
        elif new_dir.startswith('~/'):
            new_dir = home + new_dir[1:]
        for var, val in env.items():
            new_dir = new_dir.replace(f'${{{var}}}', val).replace(f'${var}', val)
        if not os.path.isabs(new_dir):
            new_dir = os.path.join(cwd, new_dir)
        cwd = os.path.realpath(new_dir)
        # Continue processing the segment — the cd itself may precede && rm on the
        # same segment line, but the check_segment call below handles that too.

    blocked, label, hit = check_segment(segment, cwd, env)
    if blocked:
        print("BLOCKED: shell command appears to modify the Kiro enforcement surface.",
              file=sys.stderr)
        print(f"  Command:  {cmd}", file=sys.stderr)
        print(f"  Mutator:  '{label}'  ->  write target: {hit}", file=sys.stderr)
        print("", file=sys.stderr)
        print("permissions.yaml and the hooks directory define the guards that constrain this "
              "agent, and permissions.yaml is hot-reloaded — an edit takes effect immediately "
              "and persists into every future session in every workspace. Changing them via "
              "shell bypasses the fs_write approval path.", file=sys.stderr)
        print("", file=sys.stderr)
        print("If this change is intended, ask the user to make it directly, or use the "
              "file-edit tools so the normal fs_write approval prompt applies. Reading or "
              "copying FROM these paths is not blocked — only writing to them.", file=sys.stderr)
        sys.exit(2)

sys.exit(0)
PYEOF

exit $?

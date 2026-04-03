#!/bin/bash
# Hook: Validate dependency files have pinned versions before writing.
# Trigger: preToolUse on fs_write
# Exit 0 = allow, Exit 2 = block (returns STDERR to LLM)

set -euo pipefail

EVENT=$(cat)

# Single Python invocation: extract all ops, validate each dependency file.
# Avoids bouncing between bash and Python, eliminates shell injection surface.
_HOOK_EVENT="$EVENT" python3 << 'PYEOF'
import json, sys, re, os

def check_package_json(content, filename):
    try:
        data = json.loads(content)
    except Exception:
        return []
    bad = []
    for section in ('dependencies', 'devDependencies', 'peerDependencies'):
        deps = data.get(section, {})
        for name, ver in deps.items():
            if re.search(r'[\^~*x]|>=|>|latest', str(ver)):
                bad.append(f'  {section}.{name}: {ver}')
    return bad

def check_requirements_txt(content, filename):
    bad = []
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith('#') or line.startswith('-'):
            continue
        if re.match(r'^[a-zA-Z0-9_.-]+\s*(\[.*\])?\s*==\s*[0-9]', line):
            continue
        bad.append(f'  {line}')
    return bad

def check_pyproject_toml(content, filename):
    bad = []
    in_deps = False
    for line in content.splitlines():
        stripped = line.strip()
        if re.match(r'\[(project\.)?dependencies\]|\[tool\.poetry\.dependencies\]', stripped):
            in_deps = True
            continue
        if stripped.startswith('[') and in_deps:
            in_deps = False
            continue
        if not in_deps:
            if 'dependencies' in line and '=' in line:
                for m in re.finditer(r'"([a-zA-Z0-9_.-]+)\s*([><!~=]+[^"]*?)"', line):
                    pkg, spec = m.group(1), m.group(2).strip()
                    if not re.match(r'^==\s*[0-9]', spec):
                        bad.append(f'  {pkg}{spec}')
            continue
        m = re.match(r'^([a-zA-Z0-9_.-]+)\s*=\s*"(.+?)"', stripped)
        if m:
            pkg, ver = m.group(1), m.group(2)
            if pkg == 'python':
                continue
            if re.search(r'[\^~*]|>=|>|<', ver):
                bad.append(f'  {pkg} = "{ver}"')
            continue
        for m2 in re.finditer(r'"([a-zA-Z0-9_.-]+)\s*([><!~=]+[^"]*?)"', stripped):
            pkg, spec = m2.group(1), m2.group(2).strip()
            if not re.match(r'^==\s*[0-9]', spec):
                bad.append(f'  {pkg}{spec}')
    return bad

def check_cargo_toml(content, filename):
    bad = []
    in_deps = False
    for line in content.splitlines():
        stripped = line.strip()
        if re.match(r'\[(.*-)?dependencies\]', stripped):
            in_deps = True
            continue
        if stripped.startswith('[') and in_deps:
            in_deps = False
            continue
        if not in_deps:
            continue
        # Simple form: serde = "1.0.200" (means ^1.0.200, unpinned)
        # Pinned form: serde = "=1.0.200"
        m = re.match(r'^([a-zA-Z0-9_-]+)\s*=\s*"(.+?)"', stripped)
        if m:
            pkg, ver = m.group(1), m.group(2)
            if not (ver.startswith('=') and not ver.startswith('==')):
                bad.append(f'  {pkg} = "{ver}" (use "={ver}" to pin exactly)')
            continue
        # Table form: serde = { version = "1.0.200", features = [...] }
        m2 = re.match(r'^([a-zA-Z0-9_-]+)\s*=\s*\{.*version\s*=\s*"(.+?)"', stripped)
        if m2:
            pkg, ver = m2.group(1), m2.group(2)
            if not (ver.startswith('=') and not ver.startswith('==')):
                bad.append(f'  {pkg} version = "{ver}" (use "={ver}" to pin exactly)')
    return bad

CHECKERS = {
    'package.json': ('Pin all versions to exact numbers (no ^, ~, *, >=, latest):', check_package_json),
    'pyproject.toml': ('Pin all versions with == (e.g., requests=="2.31.0"):', check_pyproject_toml),
    'Cargo.toml': ('Cargo treats "1.0.0" as "^1.0.0". Pin with "=1.0.0":', check_cargo_toml),
}

try:
    event = json.loads(os.environ['_HOOK_EVENT'])
except (KeyError, json.JSONDecodeError) as e:
    print(f"Hook error: failed to parse event: {e}", file=sys.stderr)
    sys.exit(1)

inp = event.get('tool_input', {})
ops = inp.get('ops', [inp])

blocked = False
for op in ops:
    path = op.get('path', '')
    content = op.get('content', '')
    if not path or not content:
        continue
    basename = os.path.basename(path)

    # Check requirements*.txt and constraints*.txt by pattern
    if re.match(r'^(requirements|constraints).*\.txt$', basename):
        bad = check_requirements_txt(content, basename)
        if bad:
            print(f'BLOCKED: Unpinned dependency versions in {basename}.', file=sys.stderr)
            print('Pin all versions with == (e.g., requests==2.31.0):', file=sys.stderr)
            print('\n'.join(bad), file=sys.stderr)
            blocked = True
        continue

    checker = CHECKERS.get(basename)
    if checker:
        hint, fn = checker
        bad = fn(content, basename)
        if bad:
            print(f'BLOCKED: Unpinned dependency versions in {basename}.', file=sys.stderr)
            print(hint, file=sys.stderr)
            print('\n'.join(bad), file=sys.stderr)
            blocked = True

sys.exit(2 if blocked else 0)
PYEOF

exit $?

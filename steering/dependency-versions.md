---
inclusion: always
---

# Dependency Versions

## New Dependencies

When adding a new dependency, use the latest stable/LTS version that has been publicly released for at least 7 days. Do not use a version released in the last week. This quarantine period reduces exposure to supply chain attacks where malicious code is injected into a new release and discovered within days.

To check release dates: use the package registry (PyPI, npm, crates.io, Maven Central) or `npm view <pkg> time` / `pip index versions <pkg>`.

## Pinning

All dependency versions MUST be pinned to exact versions. No ranges, no floating specifiers.

| Ecosystem | Pinned (correct) | Unpinned (wrong) |
|-----------|-------------------|-------------------|
| npm | `"express": "4.18.2"` | `"express": "^4.18.2"` |
| pip | `requests==2.31.0` | `requests>=2.31.0` |
| pyproject.toml | `requests=="2.31.0"` | `requests>="2.31.0"` |
| Cargo | `serde = "=1.0.200"` | `serde = "1.0.200"` |

The `check-dependency-pins.sh` hook enforces this on every file write. If the hook blocks your write, pin the version.

## Updating Dependencies

When updating an existing dependency to a newer version, apply the same 7-day quarantine. Use the latest stable version that has been released for at least 7 days.

Do not update to a version released today or this week, even if it has a feature you want. Wait for it to age.

## Exception: Security Patches

If a security scan (Dependabot, Snyk, `npm audit`, `pip-audit`, `cargo audit`, etc.) identifies a vulnerability in a current dependency and the remediation is to upgrade to a specific version, upgrade immediately. The 7-day quarantine does NOT apply to security patches.

The reasoning: the risk of running a known-vulnerable version outweighs the risk of a supply chain attack on the patch release. Security advisories are published with CVE identifiers and the fix is typically a targeted patch, not a rewrite.

## Project Overrides

Project-level version pins (`.nvmrc`, `rust-toolchain.toml`, `.python-version`, `.sdkmanrc`) always take precedence over this rule. If a project pins a specific version, use that version.

This applies to all code generation, dependency installation, project scaffolding, and infrastructure configuration.

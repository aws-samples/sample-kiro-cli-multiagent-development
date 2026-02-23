---
inclusion: always
---

# Project Dependency Isolation

## Principle

All projects MUST use language-appropriate dependency isolation to ensure reproducible builds, prevent cross-project contamination, and eliminate "works on my machine" issues. Never install project dependencies globally.

## By Language

### Python

Use `venv` for every project. No exceptions.

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

- Commit `requirements.txt` (or `pyproject.toml` with locked deps)
- Add `.venv/` to `.gitignore`
- Pin dependency versions in lock files

### JavaScript / TypeScript

npm/yarn/pnpm install to project-local `node_modules/` by default — this is already isolated. Enforce it:

- Use `.nvmrc` or `.node-version` to pin the Node.js version per project
- Use `corepack` to pin the package manager version
- Commit `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml`
- Never use `npm install -g` for project dependencies

```bash
echo "20.11.0" > .nvmrc
nvm use
corepack enable
```

### Rust

Cargo provides project-level isolation out of the box — dependencies resolve per-project via `Cargo.toml` and lock via `Cargo.lock`.

- Commit `Cargo.lock` for binaries and applications
- Use `rust-toolchain.toml` to pin the toolchain version per project

```toml
# rust-toolchain.toml
[toolchain]
channel = "1.78.0"
```

### Go

Go modules (`go mod`) provide per-project dependency isolation by default.

- Always use `go mod init` for new projects
- Commit both `go.mod` and `go.sum`
- Set `GOFLAGS=-mod=vendor` if vendoring is required

### Java / JVM

Use project-level build tool configs (Maven `pom.xml` / Gradle `build.gradle`) for dependency management. Pin the JDK version:

- Use `.sdkmanrc` (SDKMAN) or `.java-version` (jenv) to pin JDK per project
- Use Maven Wrapper (`mvnw`) or Gradle Wrapper (`gradlew`) to pin build tool versions — never rely on system-installed versions

```bash
# .sdkmanrc
java=21.0.2-tem
```

### Ruby

Use Bundler with project-local gem installation.

```bash
bundle config set --local path 'vendor/bundle'
bundle install
```

- Commit `Gemfile.lock`
- Use `.ruby-version` (rbenv/asdf) to pin Ruby version per project

## General Rules

1. **Pin everything** — language version, package manager version, dependency versions
2. **Isolation directory in `.gitignore`** — `.venv/`, `node_modules/`, `vendor/bundle/`, `target/`
3. **Lock files in version control** — always commit lock files
4. **CI must match local** — CI pipelines must use the same isolation approach and pinned versions
5. **No global installs for project deps** — if a dependency is needed by the project, it goes in the project

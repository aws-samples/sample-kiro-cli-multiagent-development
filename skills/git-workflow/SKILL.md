---
name: git-workflow
description: Git operations, branching strategies, commit conventions, and repository management. Use when working with version control, creating branches, writing commits, or resolving merge conflicts.
---

# Git Workflow

## Commit Messages

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

Good: `feat(auth): add OAuth2 support for GitHub login`
Bad: `fixed stuff`

## Branch Naming

```
<type>/<ticket>-<description>
```

Examples:
- `feature/PROJ-123-user-authentication`
- `fix/PROJ-456-null-pointer-crash`
- `hotfix/PROJ-789-security-patch`

## Common Operations

```bash
# Interactive rebase to clean up commits
git rebase -i HEAD~3

# Squash last N commits
git reset --soft HEAD~N && git commit

# Cherry-pick specific commit
git cherry-pick <sha>

# Undo last commit (keep changes)
git reset --soft HEAD~1

# Find commit that introduced bug
git bisect start
git bisect bad HEAD
git bisect good <known-good-sha>
```

## Merge Conflict Resolution

1. `git status` — identify conflicted files
2. Open file, look for `<<<<<<<`, `=======`, `>>>>>>>`
3. Keep correct code, remove markers
4. `git add <file>` then `git rebase --continue` or `git merge --continue`

## Pre-commit Checks

Always run before pushing:
- Linting/formatting
- Unit tests
- Type checking (if applicable)

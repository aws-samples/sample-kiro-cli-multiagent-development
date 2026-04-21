---
inclusion: always
---

# Issue Tracking Discipline

## Principle

Every bug fix, incident, or investigation that results in a code change MUST be documented in the project's `issues/` directory. Issue docs are the institutional memory that prevents the same problem from being solved twice.

## When to Create Issue Docs

Create an `issues/YYYY-MM-DD-<slug>/` folder with `report.md` and `summary.md` when ANY of the following are true:

- A bug is reported and fixed (by user, by tests, or discovered during review)
- A production incident is investigated (even if the root cause is external)
- A deploy fails and requires investigation beyond a simple retry
- A smoke test fails and the fix is non-obvious
- A review cycle finds critical issues that require code changes

Do NOT create issue docs for:
- Typos, formatting fixes, or trivial one-line changes
- Review suggestions that are improvements, not bugs
- Planned refactors that aren't fixing a broken behavior

## Workflow Integration

### During spec work (Phase 3: Fix)
When a review cycle finds critical or warning issues that require fixes:
1. Create `issues/YYYY-MM-DD-<slug>/report.md` describing the problem found
2. Apply the fix (as normal via fix tasks in `tasks.md`)
3. After the fix passes review, write `issues/YYYY-MM-DD-<slug>/summary.md` with root cause, fix applied, and prevention measures

### Outside spec work (ad-hoc bug fixes)
When fixing a bug that doesn't warrant a full spec:
1. Create `issues/YYYY-MM-DD-<slug>/report.md` BEFORE starting the fix
2. Investigate and fix the issue
3. Write `issues/YYYY-MM-DD-<slug>/summary.md` after the fix is verified

### Post-deploy failures
When a deploy or smoke test fails:
1. Create `issues/YYYY-MM-DD-<slug>/report.md` with reproduction steps and logs
2. Investigate and fix
3. Write `summary.md` with root cause and what prevents recurrence

## What Goes in Each File

### `report.md` — Written BEFORE or DURING investigation
- One-line summary of the problem
- Impact (who/what is affected, severity)
- Reproduction steps or error logs
- Investigation notes (what was checked, what was ruled out)

### `summary.md` — Written AFTER the fix is verified
- Root cause (the actual reason, not the symptom)
- Fix applied (what changed and where — file paths, not just descriptions)
- Prevention (tests added, monitoring, guardrails — what stops this from happening again)
- Status: RESOLVED | MITIGATED | WONT_FIX

## Rules

1. **No silent fixes** — if you change code to fix a bug, document why. A fix without a `summary.md` is incomplete work.
2. **Link issues to specs** — if the issue was found during a spec's review cycle, reference the spec slug in the report.
3. **Prevention is mandatory** — every `summary.md` must have a Prevention section. "Added a test" is the minimum. "Nothing" is not acceptable for non-trivial issues.
4. **Keep it concise** — issue docs are reference material, not narratives. Bullet points over paragraphs.

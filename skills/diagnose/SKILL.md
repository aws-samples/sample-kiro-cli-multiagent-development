---
name: diagnose
description: Investigate and fix open issues in the .kiro/issues/ folder using test-first debugging. Use when asked to diagnose, triage, or work through unresolved bug reports, or when the user mentions open issues that need fixing.
---

# Diagnose Issues

## When to Create Issue Docs

Create a `.kiro/issues/YYYY-MM-DD-<slug>/` folder with `report.md` and `summary.md` when ANY of the following are true:

- A bug is reported and fixed (by user, by tests, or discovered during review)
- A production incident is investigated (even if the root cause is external)
- A deploy fails and requires investigation beyond a simple retry
- A smoke test fails and the fix is non-obvious
- A review cycle finds critical issues that require code changes

Do NOT create issue docs for:
- Typos, formatting fixes, or trivial one-line changes
- Review suggestions that are improvements, not bugs
- Planned refactors that aren't fixing a broken behavior

## Diagnose Flow

For each unresolved issue (folders in `.kiro/issues/` without a `summary.md`):

1. **Log the issue** — create `.kiro/issues/YYYY-MM-DD-<slug>/report.md` BEFORE starting the investigation. Include: one-line summary, impact (who/what is affected and severity), reproduction steps or error logs, and investigation notes as you work.

2. **Investigate** — read `report.md`, reproduce the problem, identify the root cause. Rule out false leads and record what was checked.

3. **Write a failing test** — create a test that captures the observed broken behavior. Run it to confirm it fails for the right reason. Do not skip this step — a fix without a regression test is incomplete.

4. **Fix the code** — make the minimal change to pass the test. Run the full test suite to confirm no regressions.

   **This step is the best `/goal` candidate in the whole workflow.** The failing test from step 3 was
   written *before* the fix and by a different step than the one being verified, so it does not inherit
   the implementation's assumptions the way a self-authored test suite does. That makes it a sound stop
   condition for a self-checking loop, where most criteria are not. Invoke it yourself — `/goal` is
   user-typed, not something this skill can start:

   ```
   /goal --max 3 make `pytest tests/test_<module>.py::<test_name>` pass without breaking the rest of the suite
   ```

   Phrase the goal as the command, not the outcome. "Make the test pass" is verifiable; "fix the bug" is
   not. Do NOT extend the goal through steps 5-6 — the gates are judgments and must not be wrapped
   (see `delivery-workflow.md` → *Goal-loop tasks*).

5. **Review gate** — after the fix is applied and tests pass, delegate to `reviewer`. Wait for a PASS verdict before proceeding. This gate is **sequential** — do not launch review and security review at the same time.

6. **Security review gate** — after the review gate returns PASS, delegate to `security-reviewer`. Wait for a PASS verdict before proceeding. This gate is **sequential** — it runs only after the review gate completes.

7. **Document** — write `.kiro/issues/<slug>/summary.md` with root cause, fix applied (with file paths), prevention measures, and status.

> ⚠️ **ANTI-PATTERN — DO NOT PARALLELIZE GATES**
>
> The review gate (step 5) and security review gate (step 6) are **sequential** and must not be
> launched in parallel. The correct order is: review → wait for PASS → security review → wait for
> PASS → document. Speed does not justify skipping gates.

## File Templates

### `report.md` — Written BEFORE or DURING investigation

```markdown
# Issue: <Title>

## Summary
One-line description of the problem.

## Impact
Who/what is affected and severity.

## Reproduction
Steps to reproduce, environment details, relevant logs.

## Investigation
What was checked, what was ruled out, root cause analysis.
```

### `summary.md` — Written AFTER the fix is verified and both gates pass

```markdown
# Resolution: <Title>

## Root Cause
What caused the issue (the actual reason, not the symptom).

## Fix Applied
What changed and where — file paths, not just descriptions.

## Prevention
Tests added, monitoring, guardrails — what stops this from happening again.
"Added a test" is the minimum. "Nothing" is not acceptable for non-trivial issues.

## Status
RESOLVED | MITIGATED | WONT_FIX
```

## Rules

1. **No silent fixes** — if you change code to fix a bug, document why. A fix without a `summary.md` is incomplete work.
2. **Link issues to plans** — if the issue was found during a plan's review cycle, reference the plan slug in `report.md`.
3. **Prevention is mandatory** — every `summary.md` must have a Prevention section. "Nothing" is not acceptable for non-trivial issues.
4. **Keep it concise** — issue docs are reference material, not narratives. Bullet points over paragraphs.
5. **Failing test before fix** — always write the failing test first (step 3), then fix the code (step 4). This order is the point of the skill.

## Workflow Integration

### During plan work (Phase 3: Fix)
When a review cycle finds critical or warning issues that require fixes:
1. Create `.kiro/issues/YYYY-MM-DD-<slug>/report.md` describing the problem found
2. Write a failing test that captures the broken behavior
3. Apply the fix (via fix tasks in `tasks.md`)
4. Run the review gate → wait for PASS
5. Run the security review gate → wait for PASS
6. Write `.kiro/issues/YYYY-MM-DD-<slug>/summary.md` with root cause, fix applied, and prevention

### Outside plan work (ad-hoc bug fixes)
When fixing a bug that doesn't warrant a full plan:
1. Create `.kiro/issues/YYYY-MM-DD-<slug>/report.md` BEFORE starting the fix
2. Write a failing test
3. Investigate and fix the issue
4. Run the review gate → wait for PASS (sequential)
5. Run the security review gate → wait for PASS (sequential)
6. Write `summary.md` after both gates pass

### Post-deploy failures
When a deploy or smoke test fails:
1. Create `.kiro/issues/YYYY-MM-DD-<slug>/report.md` with reproduction steps and logs
2. Write a failing test capturing the failure
3. Investigate and fix
4. Run the review gate, then the security review gate (sequential, never parallel)
5. Write `summary.md` with root cause and what prevents recurrence

# Diagnose Issues

Review the `issues/` folder for any open reports (folders without a `summary.md`).

For each unresolved issue:

1. **Understand** — read `report.md`, reproduce the problem, identify the root cause
2. **Write a failing test** — create a test that captures the observed broken behavior. Run it to confirm it fails for the right reason.
3. **Fix the code** — make the minimal change to pass the test. Run the full test suite to confirm no regressions.
4. **Document** — write `issues/<slug>/summary.md` with root cause, fix applied, and prevention (the test itself is the minimum prevention)

Do not skip the test step. A fix without a regression test is incomplete.

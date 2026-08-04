# Test-First Development

## Principle

Define tests before or alongside implementation. Tests encode the expected behavior from the plan — they are the executable acceptance criteria.

## Depth Scaling

Test ceremony scales with plan depth. The **runnable-check floor is non-negotiable at every depth** — depth raises the ceiling, never lowers the floor.

| Depth | Required testing |
|---|---|
| `patch` | Runnable check that fails before the fix and passes after, **plus** a regression test that encodes the bug so it can never silently return |
| `prototype` | Runnable-check floor only — the smallest assert that fails if the logic breaks. No test-first ceremony required. |
| `standard` | Full test-first ceremony: test skeletons in Group 1, implementation makes them pass in later groups |
| `production` | Full test-first ceremony (as `standard`), applied per phase |

The smallest-check rule in the **Minimum Bar** section below applies regardless of depth — including `prototype`.

## Workflow Integration

### In Task Planning (`tasks.md`)
1. **Group 1 should include test skeleton tasks** — write test files with test function signatures, assertions based on plan acceptance criteria, and expected inputs/outputs. Tests will fail (red phase).
2. **Subsequent groups implement the code** — making the tests pass (green phase).
3. Tests and implementation CAN be in the same group IF they touch different files and the interface is defined in the plan.

### What Gets Tested
- **Must test**: Business logic, data transformations, API contracts, error handling
- **Should test**: Configuration validation, integration boundaries, edge cases
- **Skip**: Boilerplate, trivial getters/setters, third-party library internals

### Minimum Bar — the smallest check that fails

Even when full test-first ceremony isn't warranted, non-trivial logic MUST leave behind the smallest check that fails if the logic breaks — an assert-based self-check or one tiny test, no frameworks or fixtures required. Trivial one-liners need none. This is the floor; the workflow above is the ceiling. Logic shipped with neither a test nor a runnable check is unfinished.

### Test Structure
- One test file per module/component
- Test file naming: `test_<module>.py` (Python), `<module>.test.ts` (TS), `<module>_test.go` (Go)
- Group tests by behavior, not by method
- Each test has: Arrange, Act, Assert — no more

### Acceptance Criteria in Tasks
Every implementation task's acceptance criteria should reference specific tests:
```
Accept: `pytest tests/test_auth.py` passes — all 5 test cases green
```
This creates a hard link between the task and its verification.

## Reviewer Responsibilities
- Verify test coverage matches plan requirements
- Flag untested critical paths as **Critical**
- Flag missing edge case tests as **Warning**
- Verdict is FAIL if tests don't pass or critical paths are untested

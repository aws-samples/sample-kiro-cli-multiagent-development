---
inclusion: always
---

# Test-First Development

## Principle

Define tests before or alongside implementation. Tests encode the expected behavior from the spec — they are the executable acceptance criteria.

## Workflow Integration

### In Task Planning (`tasks.md`)
1. **Group 1 should include test skeleton tasks** — write test files with test function signatures, assertions based on spec acceptance criteria, and expected inputs/outputs. Tests will fail (red phase).
2. **Subsequent groups implement the code** — making the tests pass (green phase).
3. Tests and implementation CAN be in the same group IF they touch different files and the interface is defined in the spec.

### What Gets Tested
- **Must test**: Business logic, data transformations, API contracts, error handling
- **Should test**: Configuration validation, integration boundaries, edge cases
- **Skip**: Boilerplate, trivial getters/setters, third-party library internals

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
- Verify test coverage matches spec requirements
- Flag untested critical paths as **Critical**
- Flag missing edge case tests as **Warning**
- Verdict is FAIL if tests don't pass or critical paths are untested

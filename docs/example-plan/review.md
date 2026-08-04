# Review: Task Management API (prototype)

## Cycle 1 — 2026-07-28

Reviewing: T2 (`requirements.txt`, `requirements-dev.txt`, `.python-version`, `.gitignore`),
T3 (`tests/test_app.py`), T4 (`app.py`) against `plan.md` (depth `prototype`),
`docs/tech.md`, `decisions.md`, and the passed `design-review.md`.

`README.md` (T7) is out of scope for this cycle and its absence is not a finding.
Security is out of scope — T6 owns it.

### Verification re-run independently

| Check | Result |
|---|---|
| `.venv/bin/python -m pytest tests/ -q` | 25 passed in 0.33s |
| `.venv/bin/python -c "…openapi()['paths'].keys() >= {…}"` | OK — `/health`, `/tasks`, `/tasks/{task_id}` |
| `grep -c 'SHORTCUT:' app.py` | `3` (store, lock, body size — all three name a ceiling *and* an upgrade path) |
| `.venv/bin/pip check` | No broken requirements found |
| `.venv/bin/pip list` | `fastapi 0.139.2`, `pydantic 2.13.4`, `uvicorn 0.51.0`, `pytest 9.1.1`, `httpx2 2.7.0`, `starlette 1.3.1` — **`httpx` absent** ✓ |

### Constraint adherence (T2/T3/T4)

All clean, checked individually rather than assumed:

- **Single module** — root contains only `app.py`; no package directory. ✓
- **No validation exception handler** — `grep -nE 'exception_handler' app.py` → no match. ✓
- **No CORS middleware** — `grep -nE 'add_middleware|CORS' app.py` → no match; no middleware of any kind. ✓
- **Loopback-only host** — `app.py:178` is `host="127.0.0.1"`; `grep -rn '0\.0\.0\.0' app.py tests/` → none, and no empty-host form. ✓ (This is the mitigation the design gate's Cycle 1 Warning 1 demanded an owner for; T4 discharges it.)
- **Exact pins, five deps, no ranges** — matches the `docs/tech.md` table exactly; `pytest`/`httpx2` dev-file-only. ✓
- **Docstrings on public schemas and handlers** — present on all four schemas and all six handlers. ✓

### Pinned behaviour decisions

I exercised all four against a live `TestClient` rather than trusting the suite:

| Pinned behaviour | Implementation | Test coverage |
|---|---|---|
| `updated_at == created_at` on create | Correct — single `now` reused (`app.py:112-121`) | `test_create_task_minimal:41` ✓ |
| Empty `PUT` `{}` → `200`, no bump | Correct — early return at `app.py:153-154`; verified all fields preserved | Partial — see Suggestions |
| `null` `title`/`status` → `422`; `description` nullable and cleared by `null` | Correct — verified `{"description": null}` → `200`, `description` `None`, `updated_at` bumped | **Gap — see Warning** |
| 404 detail is `Task <id> not found` | Correct — verified literal `'Task 00000000-0000-0000-0000-000000000000 not found'` | Loose — see Suggestions |

### Critical

None.

### Warning

- **[tests/test_app.py:150-160]** The nullability rule is asymmetric by design — `title` and `status` reject explicit `null`, `description` accepts it and clears the field — but only the rejecting half is tested. `test_update_task_null_title_rejected` and `test_update_task_null_status_rejected` exist; there is **no test that `PUT {"description": null}` succeeds**. The implementation is correct (I verified: `200`, `description` becomes `None`, `updated_at` bumps), so this is a coverage gap, not a defect. It matters because the two `field_validator`s at `app.py:72-86` make a third one for `description` look like a tidy symmetry fix: a contributor adding `description_not_null` would violate a pinned Design decision with all 25 tests still green. Nothing currently anchors the asymmetry.
  - **Fix**: add one test to `tests/test_app.py` beside the two null-rejection tests:
    ```python
    def test_update_task_null_description_clears(client):
        created = client.post("/tasks", json={"title": "Keep me", "description": "clear me"}).json()
        resp = client.put(f"/tasks/{created['id']}", json={"description": None})
        assert resp.status_code == 200
        assert resp.json()["description"] is None
        assert resp.json()["title"] == "Keep me"
    ```
  - No change to `app.py` is required for this Warning.

### Suggestion

- **[tests/test_app.py:137]** `assert updated["updated_at"] > updated["created_at"]` compares ISO-8601 **strings**, and that ordering is not total across Pydantic's microsecond truncation. Verified: a zero-microsecond timestamp serializes as `2026-07-28T10:00:00Z` while a non-zero one is `2026-07-28T10:00:00.123456Z`, and `"…00.123456Z" > "…00Z"` evaluates to `False` because `'.' < 'Z'`. The test therefore false-fails whenever `created_at` lands on an exact-microsecond boundary (~1e-6 per run). It cannot pass while the bump is broken, so this is flakiness rather than a weak assertion. Fix: `from datetime import datetime` and compare `datetime.fromisoformat(updated["updated_at"]) > datetime.fromisoformat(updated["created_at"])`. While there, hoist `import time` from the function body (`:134`) to the module header — it is the only local import in the suite.

- **[tests/test_app.py:112, :165, :193]** All three 404 tests assert `"not found" in resp.json()["detail"]`. That passes for a bare `"not found"` or a detail that drops the id, so it does not lock the pinned format. Tighten one of them (`test_get_task_not_found` is the natural home) to `assert resp.json()["detail"] == f"Task {task_id} not found"` and leave the other two as substring checks.

- **[tests/test_app.py:140-147]** The no-op test asserts `title` and `updated_at` only. Since the point of the early return at `app.py:153` is that *nothing* changes, add `assert body["description"] == created["description"]` and `assert body["status"] == created["status"]` — cheap, and it covers the case where a future refactor makes the empty-body path fall through to `model_copy`.

- **[tests/test_app.py:9-10 — test invocation]** Correcting one item from the handoff: `pytest tests/ -q` does **not** pass — it fails collection with `ModuleNotFoundError: No module named 'app'`, both from the repo root and from `tests/`. Only `.venv/bin/python -m pytest` works, because `-m` puts the CWD on `sys.path` and bare `pytest` does not. T3's Verify command uses `python -m pytest`, so T3 is satisfied and this is not a Warning — but it is a trap for T7, whose Verify requires every documented command to execute as written. Either document `.venv/bin/python -m pytest tests/ -v` in the README (no new file, preferred at this depth) or add `pytest.ini` with `[pytest]\npythonpath = .`.

### Minimalism

- `shrink:` **[app.py:72-86]** The two `field_validator`s (15 lines) are not the only way to reject explicit `null`. Verified alternative: `title: str = Field(default=None, min_length=1, max_length=200)` rejects `null` with `string_type`, rejects `""` with `string_too_short`, and still allows omission — because Pydantic v2 does not validate defaults. Same for `status: TaskStatus = None`. That is a 15-line deletion. **Not a clear win, so keep or change at your discretion**: the validators buy a genuinely better 422 message (`"omit the field to leave it unchanged"`) and are self-documenting, whereas the alternative needs a `# type: ignore` and leans on an implicit `validate_default=False`. Logged so the tradeoff is a decision rather than an accident.
- `delete:` **[app.py:7]** `from __future__ import annotations` is redundant under the pinned Python 3.14.3 (`.python-version`), where annotations are already lazily evaluated. The only forward reference is `tasks_db: dict[UUID, "Task"]` at `:27`, a module-level variable annotation that is never evaluated at runtime. One line.
- `delete:` **[.gitignore:5]** `*.pyo` has not been produced since Python 3.5, and `*.pyc` at `:4` is already subsumed by `__pycache__/` at `:2`. Two lines. Trivial — mentioned only for completeness.
- The three `SHORTCUT:` markers at `app.py:18-25` are intentional, named ceilings with upgrade paths and are **not** findings. The declined `MAX_TASKS` cap is settled in `decisions.md` and is not re-litigated here.
- No dead code, no unused imports, no premature abstraction, no leftover commented-out blocks. The single-module choice is carrying its weight at ~180 lines.

Closing score: `net: -18 lines possible` — all optional, none of it required for PASS.

### Tests

- [x] All tests passing — 25 passed, 0 failed, 0 warnings (`.venv/bin/python -m pytest tests/ -q`, re-run independently)
- [x] Isolation per T3 Constraints — the `client` fixture clears `tasks_db` before every test; no cross-test state, no test-ordering dependency
- [x] Every route covered — `/health` (2), `POST /tasks` (5), `GET /tasks` (2), `GET /tasks/{id}` (3), `PUT /tasks/{id}` (7), `DELETE /tasks/{id}` (4), `/docs` + `/openapi.json` (2)
- [x] All `422` paths from T3 Accept covered — missing `title`, empty `title`, invalid `status`, malformed UUID on all three id-routes, `{"title": null}`, `{"status": null}`
- [x] `404` covered on all three id-addressed routes
- [x] `tasks_count` tracking and `updated_at` bump/no-bump covered
- [ ] **Coverage adequate for changes** — one pinned Design behaviour (`description: null` clears) has zero coverage; see Warning
- [x] No assertion weakened to make a test pass; `204` correctly asserts an empty body (`:174`)

### Verdict: FAIL

One Warning, zero Critical. The implementation itself needs **no changes** — `app.py` is correct
against all four pinned behaviour decisions and clean against every T2/T3/T4 constraint, and I
verified each one directly rather than inferring it from the passing suite. The gate fails solely
on a missing test for the `description: null` half of the nullability rule, which is a
six-line addition to `tests/test_app.py`.

Cycle 2 scope: add that one test, re-run `.venv/bin/python -m pytest tests/ -v` (expect 26 passed).
The Suggestions above do not gate and may be folded in or deferred.


## Cycle 2 — 2026-07-28

Reviewing: the Cycle 1 remediation to `tests/test_app.py` and `app.py`, re-checked against
`plan.md` (depth `prototype`), `docs/tech.md`, and `decisions.md`.

Scope note: `README.md` (T7) remains out of scope and its absence is not a finding. Security is
T6's. The `Field(default=None)` alternative is settled in `decisions.md` (2026-07-28, "validators
kept over the `Field(default=None)` alternative") and is **not** re-litigated below.

### Cycle 1 Warning — CLOSED

`test_update_task_null_description_clears` (`tests/test_app.py:170-178`) closes it. I did not
accept "a new test exists" as evidence that the gap is closed — the Warning was specifically that
*nothing anchored the asymmetry*, so I checked that the test fails under the regression it is
meant to catch. Simulated the exact scenario Cycle 1 described (a contributor adding a symmetric
`description_not_null` validator for tidiness) by subclassing `TaskUpdate` at runtime rather than
editing `app.py`:

```
original TaskUpdate(description=None) -> None (accepted)
regressed variant: rejected -> PUT would return 422 -> new test's `assert 200` fails
```

The asymmetry is now load-bearing in the suite, not just in the implementation. All four pinned
Design behaviours have real coverage.

### Verification re-run independently

| Check | Result |
|---|---|
| `.venv/bin/python -m pytest tests/ -q` | **26 passed** in 0.37s, 0 warnings |
| `.venv/bin/python -c "…openapi()['paths'].keys() >= {…}"` | OK — `['/health', '/tasks', '/tasks/{task_id}']` |
| `grep -c 'SHORTCUT:' app.py` | `3` — unchanged, all three still name a ceiling *and* an upgrade path |
| `grep -n '__future__' app.py` | absent ✓ (Cycle 1 `delete:` adopted) |
| `grep -nE 'add_middleware\|CORS\|exception_handler' app.py` | no match ✓ |
| `grep -rn '0\.0\.0\.0' app.py tests/` | none; `app.py:177` is `host="127.0.0.1"` ✓ |
| local imports in `tests/` | none — `import time` correctly hoisted to the header ✓ |
| `.venv/bin/pip check` | No broken requirements found |

Removing `from __future__ import annotations` carries a real regression risk that a passing suite
alone would not prove, since FastAPI resolves handler annotations via `get_type_hints` at
decoration time. The `openapi()` call above is the check that actually exercises it, and it
succeeds — `tasks_db: dict[UUID, "Task"]` at `app.py:27` is a module-level variable annotation
that is never evaluated, so the one forward reference is harmless. Clean.

### Suggestion adoptions verified

- **`updated_at` comparison** (`tests/test_app.py:151-156`) — now compares `datetime.fromisoformat`
  values. I confirmed the underlying flake is genuinely gone rather than assuming it:
  Pydantic serializes an exact-second UTC timestamp as `2026-07-28T10:00:00Z` and a fractional one
  as `2026-07-28T10:00:00.123456Z`; string compare of the latter against the former yields `False`,
  while `fromisoformat` on both yields `True`. Correct fix, and the inline comment explains *why*,
  which is what stops a future reader from "simplifying" it back.
- **Exact 404 detail** (`:112`) — `== f"Task {missing} not found"` on `test_get_task_not_found`;
  the other two retain substring checks, exactly as recommended.
- **No-op body test** (`:159-168`) — now creates with a `description` and `status="in_progress"`
  and asserts both preserved alongside `title` and `updated_at`. This is the version that would
  catch a refactor letting the empty-body path fall through to `model_copy`.

### Critical

None.

### Warning

None.

### Suggestion

- **[tests/test_app.py:170-178]** Two cheap hardenings to the new test, neither required:
  (a) assert the precondition — `assert created["description"] == "clear me"` — so the test cannot
  pass vacuously if `POST` ever stops persisting `description` (that path is covered by
  `test_create_task_full`, hence only a Suggestion); and (b) assert
  `datetime.fromisoformat(resp.json()["updated_at"]) > datetime.fromisoformat(created["updated_at"])`.
  Clearing a field *is* an edit, so it must take the `model_copy` branch at `app.py:155`, not the
  early return at `:153`. Without (b) the test would still pass if a future refactor misclassified
  an explicit `null` as "unset" — which is precisely the `exclude_unset` distinction the design
  depends on. This is the strongest remaining gap in the suite and it is still only a Suggestion.
- **[tests/test_app.py:159-168]** `test_update_task_empty_body_no_bump` asserts `updated_at`
  preserved but not `created_at`. One line for symmetry.
- **[tests/test_app.py:9-10 — test invocation]** Re-confirmed this cycle: `.venv/bin/pytest tests/ -q`
  still fails collection (`1 error during collection`) while `.venv/bin/python -m pytest` passes.
  Noted as already carried into T7's brief per the handoff; not a finding here, but T7's Verify
  ("every non-blocking command executes as written") will fail if the README documents bare `pytest`.

### Minimalism

- `delete:` **[.gitignore:4-5]** Carryover from Cycle 1, not adopted: `*.pyc` is subsumed by
  `__pycache__/` at `:2`, and `*.pyo` has not been produced since Python 3.5. Two lines. Trivial,
  and declining it is entirely reasonable — restated only so the ledger is accurate.
- `from __future__ import annotations` removed as suggested: **-1 line banked**, verified above as
  behaviour-preserving.
- The two `field_validator`s stay per the logged decision. The three `SHORTCUT:` markers are
  intentional named ceilings, not findings.
- The remediation added 12 test lines and deleted 1 app line. That is coverage, not bloat —
  minimalism does not apply to test code, and every added line anchors a pinned Design decision.
  No dead code, no unused imports, no premature abstraction in `app.py` at ~178 lines.

Closing score: `net: -2 lines possible` (the `.gitignore` pair). Product code is lean. Ship.

### Tests

- [x] All tests passing — 26 passed, 0 failed, 0 warnings (`.venv/bin/python -m pytest tests/ -q`, re-run independently, not taken on trust)
- [x] Isolation per T3 Constraints — the `client` fixture clears `tasks_db` before every test; no cross-test state or ordering dependency
- [x] Every route covered — `/health` (2), `POST /tasks` (5), `GET /tasks` (2), `GET /tasks/{id}` (3), `PUT /tasks/{id}` (8), `DELETE /tasks/{id}` (4), `/docs` + `/openapi.json` (2) = 26
- [x] All `422` paths from T3 Accept covered — missing `title`, empty `title`, invalid `status`, malformed UUID on all three id-routes, `{"title": null}`, `{"status": null}`
- [x] `404` covered on all three id-addressed routes; one asserts the exact pinned detail format
- [x] `tasks_count` tracking and `updated_at` bump/no-bump covered
- [x] **Coverage adequate for changes** — all four pinned Design behaviours now have tests, including the `description: null` clear that failed this box in Cycle 1
- [x] No assertion weakened to make a test pass; the two assertion changes this cycle both *strengthened* their tests
- [x] No flaky ordering assertions remain — the ISO-string comparison is gone

### Verdict: PASS

The Cycle 1 Warning is closed, and closed properly: the new test fails under the regression it was
written to catch, which is the property that was actually missing. Zero Critical, zero Warning,
26/26 passing. All five adopted Suggestions landed correctly and two of them made their tests
strictly stronger; the one declined Suggestion is documented in `decisions.md` and stays declined.
`app.py` needed no changes this cycle and still holds against every T2/T3/T4 constraint.

T5 is discharged — proceed to T6 (security review), then T7 (README). Carry into T7: document
`.venv/bin/python -m pytest tests/ -v`, never bare `pytest`, or T7's own Verify will fail. The
three Suggestions above do not gate and may be folded in or dropped.

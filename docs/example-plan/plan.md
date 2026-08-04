<!-- 
  EXAMPLE SPEC — shipped as a reference, not a live workflow artifact.
  
  This plan was produced by the architect agent at prototype depth for a simple
  FastAPI task API. It demonstrates the full artifact lifecycle: plan → design
  review (2 cycles) → code review (2 cycles) → security review (2 cycles), with
  decisions logged along the way.
  
  The `docs/tech.md` referenced below is a runtime artifact created by the
  research task (T1) in the user's project — it is not included here because it
  is project-specific and generated fresh each time.
-->

---
depth: prototype
---

# Task Management API (prototype)

## Context

We need a throwaway-grade HTTP API for managing tasks: five CRUD routes, a health
endpoint, and auto-generated OpenAPI docs. Explicitly out of scope by user
instruction: authentication, any database, and Docker. This is a local
developer-facing prototype, not a deployed service.

Verified dependency versions and API signatures live in `docs/tech.md` (verified
2026-07-28). Implementation must reference that file rather than assuming APIs.

## Decision

Single-module FastAPI app at the repo root (`app.py`), in-memory `dict` keyed by
`UUID`, Pydantic v2 schemas, pytest + `TestClient` for tests.

- **One module, not a package.** The whole surface is ~120 lines; splitting into
  `models/`, `routers/`, `storage/` would add files without adding capability.
- **`httpx2` instead of `httpx` for tests.** `starlette` 1.3.1 deprecates `httpx`
  under `TestClient`. See `docs/tech.md` — this is the non-obvious one.
- **`fastapi==0.139.2`, not `0.140.x`.** `0.140.x` shipped within the last 7 days
  and fails the dependency quarantine rule.
- **No validation exception handler.** FastAPI already returns `422` for body and
  path-param validation failures; writing one would be redundant.

### Rejected alternatives

- *Layered package structure (`app/models.py`, `app/routers/tasks.py`)* — rejected:
  ceremony with no payoff at this size.
- *`PATCH` semantics on a separate route* — rejected: the user asked for `PUT`; a
  partial-update `PUT` covers both shapes with one route.

## Design

### Data model

`TaskStatus` is `class TaskStatus(str, Enum)` with `todo`, `in_progress`, `done`.

| Schema | Fields |
|---|---|
| `TaskCreate` | `title` (required, 1–200 chars), `description` (optional, nullable, ≤2000), `status` (optional, defaults to `todo`) |
| `TaskUpdate` | all three optional; partial update applied with `model_dump(exclude_unset=True)` |
| `Task` (response) | `id` (UUID), `title`, `description`, `status`, `created_at`, `updated_at` |

Timestamps are timezone-aware UTC (`datetime.now(timezone.utc)`).

### Routes

| Method | Path | Success | Errors |
|---|---|---|---|
| `POST` | `/tasks` | `201` + `Task` | `422` invalid body |
| `GET` | `/tasks` | `200` + `list[Task]` | — |
| `GET` | `/tasks/{task_id}` | `200` + `Task` | `404` unknown id, `422` malformed UUID |
| `PUT` | `/tasks/{task_id}` | `200` + `Task` | `404`, `422` |
| `DELETE` | `/tasks/{task_id}` | `204`, empty body | `404`, `422` |
| `GET` | `/health` | `200` `{"status": "healthy", "tasks_count": N}` | — |

`/docs` and `/openapi.json` come free from FastAPI.

### Behaviour decisions worth pinning down

- **`updated_at` on create** equals `created_at`.
- **Empty `PUT` body (`{}`)** → `200` with the task unchanged and `updated_at`
  *not* bumped. A no-op should not look like an edit.
- **Explicit `null` for `title` or `status` in a `PUT`** → `422`. Only
  `description` is nullable, where `null` clears it. Without this, `{"title": null}`
  would corrupt a stored task into an invalid state.
- **404 detail** is `Task <id> not found`.

### Files

```
app.py                  # FastAPI app, schemas, in-memory store
tests/test_app.py       # pytest suite
requirements.txt        # fastapi, uvicorn, pydantic (pinned)
requirements-dev.txt    # -r requirements.txt + pytest, httpx2 (pinned)
.python-version         # 3.14.3
.gitignore              # .venv/, __pycache__/, .pytest_cache/
README.md               # endpoints, local run, tests
docs/tech.md            # verified API research (already written)
```

## Threat Model

The safety floor triggers on **network exposure**: this is an unauthenticated HTTP
service. Recorded so the exposure is a decision rather than an oversight.

**Every accepted risk below is contingent on one precondition: the service binds
loopback and is never deployed.** If that changes, auth, transport security, a
persistent store, request-size limits, and rate limiting all become mandatory
*before* exposure. The precondition is enforced by T4 (no non-loopback
`uvicorn.run`) and T7 (the documented run command), not by convention.

### Trust boundaries

The HTTP request body and path params are the only untrusted input. Pydantic
validates both at the boundary — body against `TaskCreate`/`TaskUpdate`, path
against `UUID`. Nothing else crosses a boundary: no DB, no shell, no outbound
calls, no file I/O, no template rendering.

### Data flows

Task data lives only in a process-local dict and dies with the process. No
persistence, no logs of request bodies, no third-party transmission. Blast radius
of a compromise is the in-memory task list of one local process.

### Attack surfaces

Six routes plus `/docs` and `/openapi.json`, all unauthenticated. Unbounded growth
of the task dict is the one real abuse vector — an attacker who can reach the port
can `POST` until the process exhausts memory. Mitigated by scope, not by code:
loopback-only bind, enforced by T4 and T7 and documented as prototype-only.

`max_length` caps on `title`/`description` bound *stored* per-item size only. Total
request-body size is **unbounded** — neither Starlette/FastAPI nor uvicorn 0.51.0
imposes a default body-size limit — so a single oversized or deeply nested JSON body
is fully buffered and parsed before validation rejects it with `422`, spiking memory
on the rejection path. Accepted on the same grounds as bulk `POST`: loopback-only,
prototype, never deployed. Upgrade path if ever exposed: a body-size limit at the
reverse proxy or an ASGI middleware.

**No CORS middleware** is an intentional security-relevant default. FastAPI adds
none, which is what keeps a loopback service safe from *cross-origin reads*: a
malicious page the developer visits cannot read `GET /tasks` on `127.0.0.1`. Adding
`CORSMiddleware(allow_origins=["*"])` for a frontend would hand every site the
developer browses full CRUD over the API. Two precisions, because the protection is
narrower than it looks: cross-site *writes* are blocked not by CORS but by FastAPI
requiring an `application/json` content-type — a form-encoded POST is a "simple"
request sent with no preflight, and only fails because FastAPI refuses to parse it,
so adding form parsing would quietly remove that property. And **DNS rebinding is an
accepted residual**: an attacker domain re-resolving to `127.0.0.1` is same-origin
from the browser's view, and nothing validates the `Host` header. Upgrade path:
`TrustedHostMiddleware(allowed_hosts=["127.0.0.1", "localhost"])`.

### Abuse cases

- *Unauthenticated read/write/delete of all tasks* — accepted. There is no auth by
  explicit user instruction and no sensitive data in scope. README must state this
  plainly so nobody mistakes it for deployable.
- *Memory exhaustion via bulk `POST`* — accepted for a localhost prototype; the
  upgrade path (real store, rate limiting, auth) is recorded as a `SHORTCUT:`
  marker in `app.py`.
- *Stored XSS via `title`/`description`* — out of scope: the API returns JSON and
  serves no HTML. Becomes real only if a browser client renders these unescaped.

## Risks

- **In-memory storage loses everything on restart** — intended for a prototype;
  marked with a `SHORTCUT:` comment naming the upgrade path.
- **No locking around the dict** — safe under a single-worker uvicorn, unsafe under
  `--workers > 1`, which would also give each worker a separate store. Marked
  `SHORTCUT:` and noted in the README.
- **`starlette` 1.3.1 / `httpx2` is a recent pairing** — verified working in-session
  (`docs/tech.md`); if `TestClient` misbehaves, fall back to `httpx==0.28.1` and
  accept the deprecation warning.

## Tasks

Flat list — prototype depth, no parallel groups.

- [x] **T1 — Research and document SDK/framework APIs** | `docs/tech.md`
  - **Accept**: verified import paths, signatures, and pinned versions with release
    dates for `fastapi`, `pydantic`, `uvicorn`, `pytest`, `httpx2`.
  - **Verify**: every pattern carries a source (`inspect.signature()` output or a
    live smoke run). Done — `docs/tech.md` written 2026-07-28.

- [x] **T2 — Project scaffolding** | `requirements.txt`, `requirements-dev.txt`, `.python-version`, `.gitignore`
  - **Context**: pinned, isolated deps so the app and tests are reproducible.
  - **Accept**: exact pins matching the table in `docs/tech.md`; no version ranges;
    `httpx2` and `pytest` in the dev file only.
  - **Verify**: `.venv/bin/pip install --no-input -r requirements-dev.txt` succeeds
    and `.venv/bin/pip check` reports no broken requirements.
  - **Constraints**: do not add dependencies beyond the five in `docs/tech.md`; do
    not install `httpx` (it re-triggers the starlette deprecation).

- [x] **T3 — Test suite** | `tests/test_app.py`
  - **Context**: executable acceptance criteria for every route and error path.
  - **Accept**: covers each of the six routes, `422` on validation failure (missing
    `title`, empty `title`, invalid `status`, malformed UUID, explicit
    `{"title": null}` on `PUT`), `404` on all three id-addressed routes,
    `tasks_count` tracking in `/health`, `updated_at` bumping on a real `PUT` and
    *not* bumping on `{}`, and `200` from `/docs` + `/openapi.json`.
  - **Verify**: `.venv/bin/python -m pytest tests/ -v` — all tests pass.
  - **Constraints**: isolate tests with a fixture that clears the store between
    tests; do not share state across tests. Do not weaken an assertion to make a
    test pass. If Verify fails twice for the same reason, mark `[!]` with the error
    and stop.

- [x] **T4 — Application** | `app.py`
  - **Context**: the API itself — see Design above for routes and the four pinned
    behaviour decisions.
  - **Accept**: all of T3's tests pass; docstrings on public schemas and handlers;
    `SHORTCUT:` markers naming the ceiling *and* upgrade path for the in-memory
    store, the missing lock, and the unbounded request-body size.
  - **Verify**: `.venv/bin/python -m pytest tests/ -v` passes;
    `.venv/bin/python -c "import app; assert app.app.openapi()['paths'].keys() >= {'/tasks', '/tasks/{task_id}', '/health'}"`;
    and `grep -c 'SHORTCUT:' app.py` reports at least 3.
  - **Constraints**: single module — do not create a package. Do not add an
    exception handler for validation; FastAPI's `422` is correct as-is. No auth, no
    database, no Docker. Do **not** add CORS middleware — its absence is what keeps a
    loopback service safe from the browser (see Threat Model). If you add an
    `if __name__ == "__main__": uvicorn.run(...)` block, the host must be
    `127.0.0.1` — never `0.0.0.0` or empty. If Verify fails twice for the same
    reason, mark `[!]` and stop.

- [x] **T5 — Review gate** | `.kiro/delivery/2026-07-28-task-api/review.md`
  - **Accept**: verdict `PASS`, zero critical, zero warnings.
  - **Verify**: `grep -i 'verdict.*pass' .kiro/delivery/2026-07-28-task-api/review.md`
  - **Constraints**: max 3 cycles, then escalate. Never wrap a gate in `/goal`.

- [x] **T6 — Security review gate (safety floor: network exposure)** | `.kiro/delivery/2026-07-28-task-api/security-review.md`
  - **Accept**: verdict `PASS`, zero critical, zero warnings.
  - **Verify**: `grep -i 'verdict.*pass' .kiro/delivery/2026-07-28-task-api/security-review.md`
  - **Constraints**: runs only after T5 passes — sequential, not parallel.

- [x] **T7 — README** | `README.md`
  - **Accept**: documents all six endpoints with request/response examples, local
    setup and run commands, and how to run tests. The documented run command binds
    loopback explicitly — `uvicorn app:app --host 127.0.0.1 --port 8000` — and the
    README states that changing `--host` removes the only mitigation for the
    unauthenticated surface. States plainly that the service is unauthenticated,
    in-memory, and localhost-only — not deployable.
  - **Verify**: every non-blocking command in the README executes successfully as
    written; `grep -q -- '--host 127.0.0.1' README.md` succeeds and
    `grep -q '0\.0\.0\.0' README.md` finds nothing.
  - **Constraints**: document only what shipped.

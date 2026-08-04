# Security Review: Task Management API (prototype)

## Cycle 1 — 2026-07-28

Reviewing: `app.py`, `tests/test_app.py`, `requirements.txt`, `requirements-dev.txt`,
`.python-version`, `.gitignore` — the code-level gate (T6), against `plan.md` (depth
`prototype`), `docs/tech.md`, `decisions.md`, the passed `review.md` (Cycle 2), and the
passed `design-review.md` (Security Design Review Cycle 2).

Gate triggered by the force-upgrade safety floor on **network exposure** (unauthenticated
HTTP service). `README.md` (T7) does not exist yet; its absence is not a finding, but the
statements it must carry for this posture to hold are listed under Suggestions.

Per the design gate's own closing note, its PASS does not discharge this gate. Everything
below was checked against the code and the running app, not inferred from the plan or from
the design review's conclusions. The declined `MAX_TASKS` cap and the kept `field_validator`s
are settled in `decisions.md` and are not re-litigated.

### Threat Model

Trust boundary is the HTTP request body and path params, and nothing else — verified there
is no DB, shell, `subprocess`, file I/O, outbound call, template render, deserializer, or
logger anywhere in `app.py`, so untrusted input has no injection sink to reach. Assets at
risk are the process-local task dict and the process itself (memory); blast radius dies with
the process. Attack surface is six unauthenticated routes plus `/docs` and `/openapi.json`,
reachable only from loopback. The only real abuse vector remains resource exhaustion —
unbounded task growth and unbounded request-body size — accepted by scope on the explicit
precondition that the service binds loopback and is never deployed. That precondition is the
load-bearing control, so I verified the bind rather than trusting it.

### Verification performed

| Check | Result |
|---|---|
| Loopback bind is real | `app.py:177` — `uvicorn.run("app:app", host="127.0.0.1", port=8000, reload=True)` ✓ |
| No `0.0.0.0`, `[::]`, or empty-host form anywhere in code | none — only occurrences repo-wide are in `plan.md`/`design-review.md` prose ✓ |
| No host/port override in config | no `.toml`, `.cfg`, `.ini`, `.env`, `Procfile`, `Dockerfile`, or YAML exists ✓ |
| No CORS middleware, no middleware at all | `grep -nE 'add_middleware\|CORS\|Middleware\|TrustedHost'` → only a comment at `:24` ✓ |
| No validation exception handler | `grep -n 'exception_handler'` → no match; FastAPI's native `422` is intact ✓ |
| No swallowed exception | `grep -nE 'except\|try:\|suppress\|finally'` → **zero** matches in `app.py`; nothing to swallow ✓ |
| No untrusted input reaching a sink | `grep -nE 'eval\|exec\|subprocess\|os\.system\|os\.popen\|open\(\|pickle\|yaml\.load\|__import__\|shell=True\|requests\.\|urllib\|socket'` → none ✓ |
| Error responses leak no internals | `app.debug` is `False`; 422/404 bodies checked for `/Users/`, `.venv`, `site-packages`, `app.py`, `Traceback`, `File "` — all absent ✓ |
| 404 reflection is not attacker-controlled | `app.py:136,149` interpolate a *parsed* `UUID`; `…00000000ABCD` returns canonicalised `…00000000abcd`, `content-type: application/json` ✓ |
| Mass assignment via `PUT` | `{"id":…,"created_at":…,"extra_field":…}` → `200`, `id` and `created_at` **unchanged**, extra not echoed, dict key still equals `task.id` ✓ |
| Three `SHORTCUT:` markers | `grep -c` → `3` (store `:17`, lock `:19`, body size `:21`) — each names a ceiling; one upgrade path is wrong, see Warning |
| Pins exact, match `docs/tech.md` | `fastapi==0.139.2`, `pydantic==2.13.4`, `uvicorn==0.51.0`, `pytest==9.1.1`, `httpx2==2.7.0` — no ranges, no VCS refs, no index override ✓ |
| Legacy `httpx` absent | `pip show httpx` → `Package(s) not found` ✓; `pip check` → no broken requirements ✓ |
| Venv contents | 23 packages, all expected transitives — nothing unexpected ✓ |
| Interpreter matches pin | `.python-version` `3.14.3` = `.venv/bin/python -V` ✓ |
| Suite | `.venv/bin/python -m pytest tests/ -q` → 26 passed, 0 warnings ✓ |

### Critical

None.

### Warning

- **[app.py:24]** **Confidence: High** — The unbounded-body `SHORTCUT:` marker names an
  upgrade path that does not exist: `starlette.middleware.ContentSizeLimitMiddleware`.
  Verified against the installed `starlette` 1.3.1 —
  `from starlette.middleware import ContentSizeLimitMiddleware` raises
  `ImportError: cannot import name 'ContentSizeLimitMiddleware'`, and no symbol matching
  `ContentSizeLimit`/`SizeLimitMiddleware` exists anywhere in the package. The available
  middleware submodules are `authentication, base, cors, errors, exceptions, gzip,
  httpsredirect, sessions, trustedhost, wsgi` — Starlette ships **no** body-size middleware.
  This is the marker that carries the design gate's Cycle 1 Warning 2 remediation into the
  code, and T4's Accept requires each marker to name a ceiling *and* an upgrade path; a
  fabricated API is not an upgrade path, so the ceiling survived into the code but the
  remedy did not.
  - **Attack**: The unbounded-body risk is accepted *only* while the service stays on
    loopback; the moment it is exposed, this marker is the instruction a hardening plan
    follows. That implementer hits `ImportError` and takes one of two bad branches: concludes
    Starlette offers no such control and ships the exposed service with no body limit at all,
    or hand-rolls a substitute under time pressure — most commonly trusting the client-supplied
    `Content-Length` header, which an attacker bypasses trivially with
    `Transfer-Encoding: chunked` (no `Content-Length` to check) while still streaming a
    multi-gigabyte body. Either way the one recorded mitigation for the plan's "one real abuse
    vector" is absent at precisely the moment it becomes mandatory, and the marker's presence
    makes it look handled.
  - **Remediation**: Replace the parenthetical on `app.py:24`. Keep the reverse-proxy option
    and state the ASGI option accurately, e.g.:
    `# proxy (nginx client_max_body_size) or a custom ASGI middleware — Starlette 1.3.1 ships`
    `# no body-size middleware, so it must enforce the limit on the received stream and not`
    `# trust Content-Length (chunked bodies omit it).` Do not add the middleware in this
    spec — the loopback acceptance stands and adding it would exceed prototype scope. Fix
    only the comment.

### Suggestion

- **[app.py:21-24]** **Confidence: Medium** — The unbounded-body ceiling is understated in a
  second, smaller way: it says an oversized body is "fully buffered before Pydantic rejects
  it," but FastAPI's `422` also echoes the rejected value back verbatim. Verified — a
  `POST /tasks` with a 300,000-character `title` produced a `422` whose response body was
  300,148 bytes, containing the input in the error's `input` field. So the rejection path
  costs roughly *twice* the request size plus an equal amount of outbound traffic, not once.
  Within the already-accepted class (loopback, prototype), so not a Warning; worth one clause
  on the marker while it is being corrected for the Warning above, since a reader sizing the
  ceiling for an exposure spec would otherwise budget half the real cost.

- **[app.py:151-155]** **Confidence: Medium** — `model_copy(update=…)` performs **no**
  validation, so the integrity of a stored `Task` rests entirely on `TaskUpdate` having
  filtered the client's keys first. I verified this is currently safe: Pydantic's default
  `extra='ignore'` drops unknown keys, and a `PUT` carrying `id`, `created_at`, and
  `extra_field` left all of them unchanged, keeping the dict key in sync with `task.id`.
  The protection is real but implicit — it depends on a default that is stated nowhere in the
  code or spec. A contributor who sets `extra="allow"` on `TaskUpdate` to accept flexible
  payloads (a routine, security-invisible change) would pass arbitrary client keys straight
  into an unvalidated `model_copy`, allowing `id` to be overwritten — desynchronising
  `tasks_db`'s key from the stored task and letting one task shadow another — and
  `created_at`/`updated_at` to be forged. Make it explicit: add
  `model_config = ConfigDict(extra="forbid")` to `TaskCreate` and `TaskUpdate` (import
  `ConfigDict` from `pydantic`), which turns unknown fields into a `422` and makes the
  no-mass-assignment property a stated contract rather than an inherited default. Two lines,
  no new dependency, no behaviour change for well-formed clients.

- **[app.py — no `TrustedHostMiddleware`]** **Confidence: Low** — Confirming in code what the
  design gate accepted in text: there is no `Host`-header validation, so **DNS rebinding**
  remains the one browser-reachable path to this loopback service, exactly as recorded in
  `design-review.md` Cycle 2. No code change requested — the acceptance is sound for a
  throwaway local task list with no persistence and no pivot, and the upgrade path
  (`TrustedHostMiddleware(allowed_hosts=["127.0.0.1", "localhost"])`) is already documented in
  the plan's Threat Model. Noted only so this gate records that the residual was verified as
  present-by-decision rather than missed.

- **[README.md — T7, does not exist yet]** **Confidence: Medium** — The security posture this
  gate is passing is partly carried by documentation, so T7 must state all of the following or
  the acceptance weakens:
  1. The service is **unauthenticated, in-memory, and localhost-only — not deployable**
     (already in T7 Accept).
  2. The literal run command with `--host 127.0.0.1`, and that changing `--host` removes the
     only mitigation for the unauthenticated surface (already in T7 Accept).
  3. **Single worker only** — do not pass `--workers > 1`. This is not currently in T7's Accept
     criteria. It matters twice over: it is the precondition for the `SHORTCUT:` at `app.py:19`
     (no lock around `tasks_db`), and with multiple workers each process gets its own store, so
     reads and deletes would hit inconsistent state non-deterministically.
  4. `/docs` and `/openapi.json` are **also unauthenticated** — the full API shape is readable
     by anything that can reach the port.
  5. Tests run as `.venv/bin/python -m pytest tests/ -v`, never bare `pytest` (carried from
     `review.md`; bare `pytest` fails collection and would break T7's own Verify).

  Note also that `reload=True` at `app.py:177` restarts the process on any file edit, which
  silently empties the in-memory store — worth a line so data loss reads as expected behaviour
  rather than a bug.

- **On the descoped controls**: no descoped control is being raised as mandatory. Auth, TLS, a
  database, rate limiting, and containerization are all correctly omitted for a loopback
  prototype holding no sensitive data, and the plan's Threat Model already names them as
  prerequisites *before* any exposure. Nothing found in the code changes that assessment.

### Verdict: FAIL

One Warning, zero Critical. The implementation is otherwise clean at the code level, and
cleaner than the plan strictly required: no middleware, no exception handler, no logging, no
`try`/`except` anywhere to swallow anything, no sink for untrusted input to reach, no internals
in any error body, the 404 reflection canonicalised by the UUID parser, mass assignment blocked
in practice, pins exact and matching `docs/tech.md` with legacy `httpx` genuinely absent, and
the loopback bind real at `app.py:177` with no `0.0.0.0`, `[::]`, or empty-host form anywhere in
the repo or in any config file. I confirmed each of those by execution rather than reading.

The gate fails on a single fabricated API name in a comment — `app.py:24` — which sounds
cosmetic and is not: that comment *is* the deferred mitigation for the only abuse vector this
spec accepts, and it will be read at the exact moment the loopback precondition stops holding.
Fixing it is a one-line edit to a comment, with no change to `app.py`'s behaviour and no new
dependency.

Cycle 2 scope: correct the upgrade path on `app.py:24` (optionally folding in the rejection-path
amplification clause from the first Suggestion, since it edits the same marker), then re-run
`.venv/bin/python -m pytest tests/ -q` to confirm 26 passed. The remaining Suggestions do not
gate. Every accepted risk in this PASS-pending posture rests on the loopback/never-deployed
precondition — any change that exposes the service beyond loopback invalidates this review and
requires auth, transport security, a persistent store, request-size limits, and rate limiting
before exposure.


---

## Cycle 2 — 2026-07-28

Reviewing: the Cycle 1 remediation in `app.py` and `tests/test_app.py`, re-checked against
`plan.md` (depth `prototype`), `decisions.md`, and Cycle 1 above. Scope is the delta plus a
regression sweep of everything Cycle 1 verified by execution — I re-ran the checks rather than
carrying them forward, and re-derived the orchestrator's two reported results independently.

### Threat Model

Unchanged from Cycle 1, and I re-confirmed the reasons it is unchanged rather than assuming it.
The remediation touched two Pydantic `model_config` lines, one comment block, and two tests; it
added no middleware, no exception handler, no dependency, and no new sink. `grep` for
`add_middleware|CORS|Middleware|TrustedHost|exception_handler|except |try:|eval(|exec(|subprocess|os.system|open(|pickle|yaml.load|requests.|urllib|socket|logging`
over `app.py` returns **zero** matches, so the trust boundary is still the request body and path
params only, with no injection sink behind it. Assets, blast radius, and the loopback
precondition are all as recorded. One thing did change, in the right direction: `extra="forbid"`
narrowed the input contract at the boundary, which removed an existence oracle (see below).

### Cycle 1 Warning — CLOSED

**[app.py:21-28]** The fabricated `starlette.middleware.ContentSizeLimitMiddleware` upgrade path
is gone and what replaced it is accurate. Verified independently, not taken on report:

| Claim now in the marker | Verification |
|---|---|
| `starlette` is 1.3.1 | `starlette.__version__` → `1.3.1` ✓ |
| Starlette 1.3.1 ships **no** body-size middleware | `pkgutil.iter_modules` over `starlette.middleware.__path__` → `authentication, base, cors, errors, exceptions, gzip, httpsredirect, sessions, trustedhost, wsgi`; `grep -rniE 'ContentSizeLimit|SizeLimitMiddleware|max_body|body_size|client_max'` across the whole installed package → **no matches** ✓ |
| The old name is genuinely absent | `from starlette.middleware import ContentSizeLimitMiddleware` → `ImportError: cannot import name 'ContentSizeLimitMiddleware'` ✓ |
| uvicorn 0.51.0 sets no default body-size limit | `grep` for `max_body|body_size|limit_body|client_max` across installed `uvicorn` → only a websockets `client_max_window_bits`, unrelated ✓ |
| `nginx client_max_body_size` is the reverse-proxy option | correct directive name for the stated purpose ✓ |
| A custom middleware must cap the received stream and not trust `Content-Length` | correct, and it is the planific trap the Cycle 1 attack scenario named — chunked bodies omit `Content-Length`, so header-only enforcement is bypassed with `Transfer-Encoding: chunked` ✓ |

The marker no longer sends a hardening implementer into an `ImportError` and then into a
header-trusting hand-rolled substitute. It names a ceiling and a real upgrade path, satisfying
T4's Accept. `grep -c 'SHORTCUT:' app.py` → **3** (`:17` store, `:19` lock, `:21` body size),
each still naming a ceiling. The Cycle 1 Suggestion about rejection-path cost was folded into
the same marker as suggested.

### Regression check on `extra="forbid"`

This was the substantive change, and the orchestrator was right to ask whether it weakened
anything. It did not. Findings, all by execution:

**No existence oracle was created — one was closed.** Body validation runs before the handler,
so it fires identically whether or not the task exists. Probing a real vs. a nonexistent id:

| `PUT` body | real task | missing task | |
|---|---|---|---|
| `{"title":"x"}` | 200 | 404 | differs — the documented Design contract |
| `{}` | 200 | 404 | differs — the documented Design contract |
| `{"bogus":1}` | 422 | 422 | same, no oracle |
| `{"title":"x","bogus":1}` | 422 | 422 | same, no oracle |
| `{"title":null}` | 422 | 422 | same, no oracle |
| `{"status":"flying"}` | 422 | 422 | same, no oracle |

The two differing rows are `200`-vs-`404` on a *well-formed* body, which is the pinned Design
contract (`404` unknown id), not a leak introduced here. More usefully, the change went the
protective direction on the unknown-field row: I reconstructed the pre-change schema with
`extra="ignore"` and confirmed `{"bogus":1,"id":…,"created_at":…}` validated cleanly to
`changes == {}`, which meant the handler *was* reached and returned `200` for a real task
vs. `404` for a missing one — a genuine existence oracle on a payload carrying no valid fields.
Both are now `422`. `extra="forbid"` strictly reduced the distinguishable-response surface.

**All four pinned Design behaviours intact**: `updated_at == created_at` on create ✓; empty
`PUT {}` → `200`, task unchanged, `updated_at` **not** bumped ✓; explicit `null` for `title`
and for `status` → `422` while `null` for `description` clears it with a bumped `updated_at` ✓;
`404` detail exactly `Task <id> not found` ✓. `404` still returned for `GET`/`PUT`/`DELETE` on a
missing id. `/docs` and `/openapi.json` still `200`.

**Store integrity under a rejected `PUT`**: sending `id` + `created_at` now yields `422`, and
afterwards the dict key still equals `task.id`, `created_at` is byte-identical to the original,
and the task count is unchanged — so the `model_copy(update=…)` path, which performs no
validation of its own, is now guarded by a *stated* contract rather than an inherited default.
`additionalProperties: false` appears on both `TaskCreate` and `TaskUpdate` in the OpenAPI
schema, and only those two; the server-constructed `Task` response model is untouched.

**Nothing else moved**: `app.debug` is `False`; the `422` for a reflected unknown key
(`<script>alert(1)</script>` as a field name) returns `content-type: application/json` with the
key echoed only in a JSON string, so there is no HTML sink; `422` and `404` bodies contain no
`/Users/`, `.venv`, `site-packages`, `app.py`, `Traceback`, or `File "`. Pins unchanged and
exact (`fastapi==0.139.2`, `pydantic==2.13.4`, `uvicorn==0.51.0`, `pytest==9.1.1`,
`httpx2==2.7.0`); `pip check` clean; legacy `httpx` still absent. The venv lists 24 entries
against Cycle 1's 23 — I enumerated all of them and every one is an expected transitive of the
five pins plus `pip`/`truststore`, so this is a counting difference, not a new install, and not a
finding.

**Independent re-derivation of the reported results**: `.venv/bin/python -m pytest tests/ -q` →
**28 passed** (26 + the two new tests), and `grep -c 'SHORTCUT:' app.py` → **3**. Both match what
was reported. The two new tests assert the right things: `test_update_task_rejects_unknown_field`
checks the `422` *and* re-reads the task to confirm `created_at` survived, which is the property
that actually matters rather than just the status code.

### Critical

None.

### Warning

None. The single Cycle 1 Warning is closed and the remediation introduced no new Warning.

### Suggestion

- **[app.py:21-28]** **Confidence: High** — `extra="forbid"` added a new component to the
  rejection-path cost that the freshly corrected marker does not size. The marker now says the
  rejection path costs "~2x the request size plus equal outbound traffic," which I confirmed is
  accurate for the case it describes — a single oversized field value measures `out/in = 1.00x`
  (300,013 in → 300,148 out). But rejected *unknown keys* are reported one error object per key
  with no cap, and each object carries ~130 bytes of fixed JSON boilerplate regardless of how
  small the key is:

  | Body | In | Out | Ratio | Errors |
  |---|---|---|---|---|
  | one 300,000-char `title` | 300,013 | 300,148 | 1.00x | 1 |
  | 10,000 tiny unknown keys | 118,905 | 988,902 | **8.32x** | 10,000 |
  | 50,000 tiny unknown keys | 638,905 | 4,988,902 | **7.81x** | 50,000 |

  Pydantic applies no error-count cap (50,000 extras → 50,000 error objects). Pre-change these
  keys were silently dropped and the response was a single ~250-byte task, so this ratio is new
  this cycle. It is **not** a Warning: under the verified loopback precondition the only client
  is local, a local attacker has strictly cheaper ways to exhaust the process, and the response
  is bounded once any body-size limit is in place. It is worth one clause because this marker is
  read at exposure time and a reader sizing a limit from "~2x" would under-budget by ~4x — and,
  more usefully, because a body-size cap alone bounds this only loosely: 1 MB of tiny keys is
  still ~78,000 errors ≈ 7.8 MB outbound. If the marker is touched again, note that a hardening
  spec should cap the reported error count as well as the body size.

- **[README.md — T7, still does not exist]** **Confidence: Medium** — Carried forward unchanged;
  its absence remains not a finding. Confirmed the orchestrator is routing all five Cycle 1 items
  into T7's brief (not-deployable, the literal `--host 127.0.0.1` command and what changing it
  costs, single-worker-only, `/docs` + `/openapi.json` also unauthenticated, and
  `.venv/bin/python -m pytest` rather than bare `pytest`), plus the `reload=True` store-emptying
  note. One addition now that `extra="forbid"` is in: unknown JSON fields are rejected with `422`
  rather than ignored, which is a client-visible contract change worth a line in the endpoint docs.

- **[app.py — no `TrustedHostMiddleware`]** **Confidence: Low** — DNS rebinding remains the
  accepted residual, unchanged and re-confirmed absent-by-decision per Cycle 1 and the design
  gate. No code change requested.

- The declined `MAX_TASKS` cap and the kept `field_validator`s remain settled in `decisions.md`
  and are not re-litigated. The new `extra="forbid"` decision is logged there too, with rationale
  matching what shipped.

### Verdict: PASS

Zero Critical, zero Warning. The Cycle 1 Warning at `app.py:21-28` is **closed**: the fabricated
`ContentSizeLimitMiddleware` is gone, and I verified against the installed `starlette` 1.3.1 that
its replacement is true in every particular — no body-size middleware exists in the package, the
old symbol genuinely fails to import, uvicorn 0.51.0 imposes no default limit, and the
`Content-Length`/chunked caveat correctly names the trap the Cycle 1 attack scenario predicted an
implementer would fall into.

The `extra="forbid"` remediation weakened nothing. Specifically, on the ordering question: body
validation precedes the handler uniformly, so `422` is returned for a malformed body whether or
not the task exists — no existence information is leaked, and the change in fact *closed* a
pre-existing oracle where an unknown-fields-only `PUT` returned `200` for a live task and `404`
for a missing one. All four pinned Design behaviours, the `404` paths on all three id-addressed
routes, the no-op `{}` semantics, the `null`-handling asymmetry, error-body hygiene, and the exact
dependency pins all verified intact by execution. Store integrity holds after a rejected `PUT`.

The one new observation — that forbidding extras made the rejection path an ~8x uncapped outbound
amplifier — sits inside the unbounded-body class this plan already accepts by scope, has no
exploitation path while the service stays on loopback, and is recorded as a Suggestion so a future
hardening spec sizes its limits correctly. It does not gate.

Every accepted risk in this PASS continues to rest on the single precondition that the service
binds loopback and is never deployed, verified again this cycle at `app.py:177` with no
`0.0.0.0`, `[::]`, or empty-host form anywhere in the repo and no config file capable of
overriding it. Any change that exposes the service beyond loopback invalidates this review and
requires auth, transport security, a persistent store, request-size **and error-count** limits,
and rate limiting before exposure.

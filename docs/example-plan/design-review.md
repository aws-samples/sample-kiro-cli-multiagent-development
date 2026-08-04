# Design Review: Task Management API (prototype)

## Security Design Review — Cycle 1 — 2026-07-28

Reviewing: `plan.md` (depth `prototype`), Threat Model section, against `docs/tech.md`.
Scope: design only — no implementation exists. Gate triggered by the force-upgrade
safety floor on **network exposure** (unauthenticated HTTP service).

### Threat model assessment

The plan's Threat Model is unusually good for prototype depth and correct on the
substance that matters:

- **Trust boundaries** are enumerated accurately. HTTP body and path params are
  genuinely the only untrusted input, and the claim that nothing else crosses a
  boundary holds against the Design section — no DB, no shell, no `subprocess`, no
  file I/O, no outbound calls, no template rendering. There is no injection sink for
  untrusted input to reach.
- **Data flows** are correct. Process-local dict, no persistence, no request-body
  logging, no third-party transmission. Blast radius is accurately stated.
- **Abuse cases** name the right three and, critically, *label them as accepted
  decisions rather than omissions*. The XSS dismissal is correctly reasoned: a
  JSON-only API that serves no HTML has no sink, and the caveat about a future
  browser client rendering unescaped is the right conditional.
- **Secrets**: none in scope. Nothing to leak, nothing to rotate. Correctly silent.
- **Authorization model**: explicitly "everything is public," which is a stated rule
  rather than an implicit one. For a loopback prototype holding no sensitive data,
  that is an acceptable model.

Green-field repo — no pre-existing security invariants, honeypots, alarms, or auth
boundaries for this design to violate. No collision findings.

Two gaps remain, both in the *bounds* category, and both are cheap spec-text edits
rather than descoped controls. Neither asks for auth, TLS, a database, rate
limiting, or containers.

### Critical

None.

### Warning

- **[plan.md — Threat Model → Attack surfaces]** **Confidence: High** — The sole
  stated mitigation for the only real abuse vector is not enforced by any task. The
  section says unbounded growth is "Mitigated by scope, not by code: bind to
  `127.0.0.1` only," but the loopback bind appears nowhere in Design, Files, or the
  Accept criteria of T4 or T7. `uvicorn`'s `--host` default *is* `127.0.0.1`, so the
  safe behaviour is the default — but nothing in the plan records that as a security
  requirement, and T7 is the task that publishes the run command developers will
  actually copy.
  - **Attack**: A developer follows a README that documents
    `uvicorn app:app --host 0.0.0.0` (the most copy-pasted uvicorn invocation there
    is, and the one every container tutorial uses) while on shared Wi-Fi. Anyone on
    that LAN then has unauthenticated read, write, and delete over every task, plus
    the ability to `POST` until the process exhausts memory. The accepted-risk
    reasoning in the Threat Model — "no auth is fine because it is loopback-only" —
    silently stops being true, and nothing in the plan or tests detects it.
  - **Remediation**: Add to **T7 Accept**: "the documented run command binds
    loopback explicitly — `uvicorn app:app --host 127.0.0.1 --port 8000` — and the
    README states that changing `--host` removes the only mitigation for the
    unauthenticated surface." Add to **T4 Constraints**: "do not add an
    `if __name__ == '__main__': uvicorn.run(...)` block with any host other than
    `127.0.0.1`." In the Threat Model, change "bind to `127.0.0.1` only" to reference
    the task that enforces it, so the mitigation has an owner.

- **[plan.md — Threat Model → Attack surfaces]** **Confidence: High** — The claim
  "`max_length` caps on `title`/`description` bound per-item size" overstates the
  bound. Pydantic `max_length` is evaluated *after* Starlette has read the full
  request body into memory and after the JSON parser has built the document.
  Starlette and FastAPI impose no default request-body size limit, and `uvicorn`
  0.51.0 has no body-size flag (`--limit-concurrency` and `--limit-max-requests`
  bound connections and request count, not bytes). So the caps bound what gets
  *stored*, not what gets *allocated*.
  - **Attack**: A single `POST /tasks` carrying a multi-gigabyte JSON body, or a
    deeply nested JSON document, is fully buffered and parsed before validation
    rejects it with `422` — one request, no auth, no repetition needed, and the
    memory spike happens on the rejection path where the Threat Model believes a
    bound exists. Deep nesting additionally drives parser recursion. This is the same
    accepted memory-exhaustion class, but the plan currently asserts it is mitigated
    when it is not.
  - **Remediation**: Do not add body-size middleware — that fights the single-module
    scope for a loopback service. Fix the claim instead. Replace the sentence with:
    "`max_length` caps on `title`/`description` bound *stored* per-item size only.
    Total request-body size is **unbounded** — there is no Starlette or uvicorn
    default limit — so a single oversized or deeply nested body can spike memory
    before validation rejects it. Accepted on the same grounds as bulk `POST`:
    loopback-only, prototype, never deployed. Upgrade path if this is ever exposed:
    a body-size limit at the reverse proxy or an ASGI middleware." Add the same
    ceiling to the `SHORTCUT:` marker required by T4.

### Suggestion

- **[plan.md — Threat Model → Abuse cases, memory exhaustion]** **Confidence:
  Medium** — The cheapest available control for the accepted memory-exhaustion case
  is a store-size cap, not rate limiting: a module-level `MAX_TASKS` constant and a
  `507`/`429` once the dict is full. That is roughly two lines, needs no dependency,
  no middleware, and no auth, and it converts "mitigated by scope" into "mitigated by
  code" for the abuse case the plan itself calls "the one real abuse vector." Worth
  considering precisely because it is smaller than the `SHORTCUT:` comment describing
  its absence. Raised as a Suggestion, not a Warning: with the loopback bind pinned
  per the first Warning, scope-based acceptance is legitimate at this depth.

- **[plan.md — Design → Files / Threat Model → Attack surfaces]** **Confidence:
  Medium** — Record "no CORS middleware" as an intentional security-relevant default.
  FastAPI adds none by default, which is what makes a loopback service safe from the
  browser: a malicious page the developer visits cannot read `GET /tasks` from
  `127.0.0.1:8000`, and a JSON `POST` triggers a preflight that fails. That safety
  is invisible in the current plan, so a future contributor adding
  `CORSMiddleware(allow_origins=["*"])` for a frontend would silently hand every
  website the developer browses full CRUD over the API. One line in the Threat Model
  and a T4 constraint ("do not add CORS middleware") preserves the property.

- **[plan.md — Threat Model, overall framing]** **Confidence: Low** — The accepted
  risks are all conditional on one precondition — loopback-only, never deployed — but
  that precondition is stated as an aside inside the mitigation prose. Promoting it
  to an explicit opening line ("every accepted risk below is contingent on the
  service binding loopback and never being deployed; if that changes, auth, transport
  security, a persistent store, request-size limits, and rate limiting all become
  mandatory before exposure") makes the boundary of the acceptance auditable, and
  gives a future upgrade spec a single sentence to invalidate.

### Verdict: FAIL

Two Warnings, zero Critical. Both are corrections to the Threat Model text plus
Accept/Constraint lines on existing tasks T4 and T7 — no new dependency, no new
module, and no descoped control is being demanded. The unauthenticated, in-memory,
localhost-only posture is **accepted as appropriate** for this prototype; what fails
the gate is that one stated mitigation is unowned and another does not exist as
described.

Fix both, then re-run this gate as Cycle 2. This design review does **not** discharge
the code-level security review at T6 — that gate still runs against `app.py` once it
exists.


## Security Design Review — Cycle 2 — 2026-07-28

Reviewing: amended `plan.md` (depth `prototype`) + `decisions.md`, against Cycle 1
findings and `docs/tech.md`. Scope: design only — no implementation exists yet. Gate
triggered by the force-upgrade safety floor on **network exposure**.

### Cycle 1 disposition

- **Warning 1 — unowned loopback mitigation: CLOSED.** The mitigation now has named
  owners in all three places it needed them. Threat Model preamble: "The precondition
  is enforced by T4 (no non-loopback `uvicorn.run`) and T7 (the documented run
  command), not by convention." Attack surfaces now reads "loopback-only bind,
  enforced by T4 and T7." T4 Constraints pin the host to `127.0.0.1` and explicitly
  exclude `0.0.0.0` *and* empty — the empty-host case matters, because `uvicorn.run`
  with `host=""` binds all interfaces just as `0.0.0.0` does, and Cycle 1's
  remediation only named `0.0.0.0`. T7 Accept carries both the literal run command
  and the required README statement that changing `--host` removes the only
  mitigation. The attack path in Cycle 1 (a copy-pasted `--host 0.0.0.0` on shared
  Wi-Fi) is now contradicted by the plan text a task will be graded against.

- **Warning 2 — overstated `max_length` bound: CLOSED.** The claim is now accurate
  rather than softened: caps bound *stored* per-item size only, total request-body
  size is stated as unbounded, the absence of a Starlette/FastAPI default and of any
  uvicorn 0.51.0 body-size flag is named (consistent with `docs/tech.md`), and the
  rejection-path memory spike is described where Cycle 1 said the plan wrongly
  believed a bound existed. Acceptance is scoped to the loopback precondition and the
  upgrade path (reverse-proxy limit or ASGI middleware) is recorded. T4 Accept now
  requires a `SHORTCUT:` marker for unbounded body size alongside the store and lock
  markers, so the ceiling survives into the code.

Suggestions: CORS default and precondition framing both adopted, and the CORS
adoption is stronger than what Cycle 1 asked for — the property is recorded in the
Threat Model *and* enforced as a T4 Constraint. The `MAX_TASKS` cap is declined with
a logged rationale in `decisions.md`; the reasoning (a route contract plus a test,
not two lines; scope-based acceptance is legitimate once the bind is enforced) is
sound at prototype depth and is **not re-raised**.

No new collision surface: still a green-field repo with no pre-existing guards,
alarms, or auth boundaries for this design to violate. The amendments add no new
trust boundary, data sink, or dependency.

### Critical

None.

### Warning

None.

### Suggestion

- **[plan.md — Threat Model → Attack surfaces, CORS paragraph]** **Confidence:
  Medium** — The new CORS paragraph is directionally right and its instruction ("do
  not add CORS middleware") is the correct call, but its justification is stated
  absolutely and has one residual browser-reachable path: **DNS rebinding**. A page
  on an attacker-controlled domain served with a short-TTL record that re-resolves to
  `127.0.0.1` becomes *same-origin* with the service from the browser's point of
  view, so the same-origin policy that the paragraph relies on stops applying and the
  responses become readable. FastAPI adds no `TrustedHostMiddleware` by default, so
  nothing validates the `Host` header. Not raised as a Warning: it needs an
  attacker-controlled domain plus a live page while the prototype is running, the
  asset is a throwaway local task list with no persistence and no pivot (no DB, no
  shell, no outbound calls), and the plan's opening precondition already fences the
  acceptance. Worth one hedging clause so the claim is not relied on as absolute:
  note rebinding as an accepted residual and record
  `TrustedHostMiddleware(allowed_hosts=["127.0.0.1", "localhost"])` as its upgrade
  path. Related accuracy note for the same paragraph: what actually blocks a
  cross-site *write* is not CORS but FastAPI's requirement of an
  `application/json` content-type — a form-encoded or `text/plain` POST is a "simple"
  request that is sent without a preflight and would only fail because FastAPI
  refuses to parse it as a body. That is worth a clause because it identifies the
  property a future contributor could quietly remove by adding form parsing.

- **[plan.md — T7 Verify]** **Confidence: Medium** — T7 now owns half the loopback
  mitigation, but its Verify ("every command in the README executes successfully as
  written") cannot check it: `uvicorn app:app --host 127.0.0.1 --port 8000` does not
  exit, so a verifier either blocks or skips it, leaving the mitigation graded by
  Accept prose alone. Make it machine-checkable instead — e.g. assert `README.md`
  contains `--host 127.0.0.1` and contains no `0.0.0.0`. Cheap, non-blocking, and it
  turns the enforcement Cycle 1 asked for into something a gate can actually fail on.

- **[plan.md — T4 Verify]** **Confidence: Low** — The `SHORTCUT:` markers are the
  artifact that carries the Warning 2 remediation into the code and feeds a future
  hardening spec, but they appear only in Accept, with nothing in Verify checking
  they exist. A count assertion over `app.py` for the three required markers
  (in-memory store, missing lock, unbounded body size) closes the loop at no cost.

### Verdict: PASS

Both Cycle 1 Warnings are closed, zero Critical and zero Warnings remain, and the two
adopted Suggestions were implemented more completely than requested. The three
Suggestions above do not block: they are text hedges and verification-tightening, and
Suggestions are logged rather than gating.

Design gate cleared — implementation may begin. Two standing reminders: this review
does **not** discharge the code-level security review at T6, which still runs against
`app.py` once it exists (a swallowed exception, a stray `0.0.0.0`, or a missing
`SHORTCUT:` marker is only visible in code); and every accepted risk here rests on
the loopback/never-deployed precondition, so any change that exposes the service
beyond loopback invalidates this PASS and requires auth, transport security, a
persistent store, request-size limits, and rate limiting before exposure.

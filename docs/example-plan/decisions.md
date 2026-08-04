# Decisions: Task Management API (prototype)

## 2026-07-28 — fastapi pinned to 0.139.2, not 0.140.x
**Context**: `fastapi` 0.140.0–0.140.9 all shipped between 2026-07-24 and 2026-07-28.
**Decision**: Pin `fastapi==0.139.2` (released 2026-07-16).
**Rationale**: The 7-day dependency quarantine. 0.139.2 is the newest eligible release.

## 2026-07-28 — `httpx2` instead of `httpx` for tests
**Context**: `starlette` 1.3.1 emits `StarletteDeprecationWarning` when `TestClient` runs on the legacy `httpx` package.
**Decision**: Pin `httpx2==2.7.0` as a dev-only dependency and do not install `httpx`.
**Rationale**: Verified in-session that `httpx2` removes the warning entirely (checked under `warnings.simplefilter("error", DeprecationWarning)`) while `httpx==0.28.1` only works with the warning. `httpx2` 2.9.1 is latest but inside the quarantine window; 2.7.0 (2026-07-14) is eligible.

## 2026-07-28 — MAX_TASKS store cap declined
**Context**: The security design review suggested a two-line `MAX_TASKS` cap returning `429`/`507` to convert the accepted memory-exhaustion risk from scope-mitigated to code-mitigated.
**Decision**: Declined for this plan. Recorded as an upgrade path in the `SHORTCUT:` marker instead.
**Rationale**: It is a behaviour the user did not request, and it needs a route contract plus a test to be real — not actually two lines. With the loopback bind now enforced by T4/T7 and the exposure documented, scope-based acceptance is legitimate at prototype depth. This becomes mandatory the moment the service is exposed beyond loopback.

## 2026-07-28 — empty `PUT` body is a 200 no-op
**Context**: `PUT /tasks/{id}` with `{}` needed defined semantics.
**Decision**: Return `200` with the task unchanged and do not bump `updated_at`.
**Rationale**: Cheaper than a "at least one field" validator, and a no-op should not look like an edit in the timestamps.


## 2026-07-28 — validators kept over the `Field(default=None)` alternative
**Context**: Review Cycle 1 logged a verified 15-line-shorter alternative to the two `field_validator`s that reject explicit `null` for `title`/`status` (`title: str = Field(default=None, ...)`, relying on Pydantic v2 not validating defaults).
**Decision**: Keep the validators.
**Rationale**: The alternative needs a `# type: ignore` and leans on implicit `validate_default=False` — a reader cannot see why it works. The validators produce an actionable 422 (`omit the field to leave it unchanged`) and are self-documenting. Not re-litigated in later cycles.


## 2026-07-28 — `extra="forbid"` adopted on `TaskCreate`/`TaskUpdate`
**Context**: Security review Cycle 1 noted that `model_copy(update=...)` performs no validation, so the no-mass-assignment property rested entirely on Pydantic's unstated default `extra='ignore'`. A contributor setting `extra="allow"` could let a client overwrite `id` (desyncing the store key) or forge `created_at`.
**Decision**: Added `model_config = ConfigDict(extra="forbid")` to both input schemas, plus two tests asserting unknown keys are rejected with 422 and `created_at` is unchanged.
**Rationale**: Input validation at a trust boundary is explicitly outside the minimalism ladder. Two lines turn an inherited default into a stated contract; well-formed clients see no behaviour change.

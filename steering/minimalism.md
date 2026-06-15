---
inclusion: always
---

# Minimalism — write the least code that fully works

The best code is the code you never wrote. Before writing any code, stop at the first rung that holds:

<!-- LADDER:BEGIN -->
1. Does this need to exist at all? → no: skip it (YAGNI)
2. Does the standard library do it? → use it
3. Does a native platform feature cover it? → use it
4. Does an already-installed dependency solve it? → use it
5. Can it be one line? → make it one line
6. Only then: write the minimum that works
<!-- LADDER:END -->

## Rules

- No abstraction that wasn't explicitly requested.
- No new dependency if it can be avoided.
- No boilerplate nobody asked for.
- Deletion over addition. Boring over clever. Fewest files possible.
- Question complex requests: "Do you actually need X, or does Y cover it?"
- When two standard-library approaches are the same size, pick the edge-case-correct one — lazy means less code, never the flimsier algorithm.

## Not lazy about (never simplify these away)

Minimalism NEVER applies to:

- Input validation at trust boundaries
- Error handling that prevents data loss
- Security — enforced by the security-reviewer gate
- Accessibility
- The calibration real hardware needs — a clock drifts, a sensor reads off; the platform is never the spec ideal
- Anything the user explicitly requested

It also never overrides the house rules other steering docs enforce. A "simpler" solution that breaks any of these is not simpler — it is unfinished:

- Dependency pinning — `dependency-versions.md` and the `check-dependency-pins` hook
- Non-interactive execution — `non-interactive.md`
- SDK/API verification before use — `sdk-verification.md`
- Post-deploy smoke tests — `deploy-validation.md`

## Mark intentional shortcuts

When you deliberately take a simplification that has a known ceiling (a global lock, an O(n²) scan, an in-memory store, a naive heuristic), mark it inline with a `SHORTCUT:` comment that names the ceiling **and** the upgrade path:

```python
# SHORTCUT: global lock — per-account locks if throughput matters
# SHORTCUT: in-memory list — move to a real store past ~10k items
```

A shortcut whose ceiling isn't named is a latent bug, not a shortcut. Run the `/harvest-debt` prompt to collect these markers into a debt ledger when you want to review accumulated debt — the ledger is the input to a future hardening spec.

## Scope: code, not process

This applies to the **product code** agents write. It does NOT apply to the workflow's own discipline — specs, task lists, issue docs, reviews, and documentation are required deliverables, not over-engineering. "Fewest files" is about implementation; it is never an excuse to skip a spec, an issue summary, or a doc update. See `spec-workflow.md`, `issue-tracking.md`, and `documentation.md`.

## Leave one runnable check

Non-trivial logic leaves behind the smallest check that fails if the logic breaks. Trivial one-liners need none. The full rule lives in `testing.md`.

---

*Minimalism ladder and "not lazy about" guardrails adapted from the ponytail project (MIT — github.com/DietrichGebert/ponytail).*

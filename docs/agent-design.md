# Agent Design Decisions

## Model Tiering

The agent roster uses three model tiers, matched to the cognitive demands of each role:

**Opus (planning and review):** The architect, reviewer, and security-reviewer use Opus. These roles require judgment: deciding what to build, evaluating whether an implementation is correct, and spotting subtle vulnerabilities. Judgment-heavy work benefits from the strongest available model.

**Sonnet (implementation):** The coder and ops agents use Sonnet. Implementation is mechanical once the plan and task plan exist. The agent follows instructions, writes code, and self-verifies against tests. Sonnet handles this well and costs less per token.

**Haiku (documentation):** The docs agent uses Haiku. Documentation is low-risk prose: it summarizes what was built, updates READMEs, and writes inline comments. Errors are caught in review and are cheap to fix. No reason to spend Opus tokens on this.

## Steering Per Agent

### Applied 2026-07-28

Each agent declares an explicit list of the steering files it needs, instead of loading all nine via a
glob. The orchestrator is the exception and keeps both globs — see *Why the orchestrator keeps globs*.

| Agent | Steering loaded | Bytes | Reduction |
|-------|-----------------|-------|-----------|
| architect | all 9 via glob, plus the project-level glob | 53,495 | — |
| coder | all 9 | 53,495 | none |
| ops | all 9 | 53,495 | none |
| reviewer | all except `documentation` | 51,667 | 3% |
| security-reviewer | delivery-workflow, cli-execution, artifact-locations, dependency-versions | 38,790 | 28% |
| docs | documentation, artifact-locations, cli-execution, delivery-workflow, dependency-versions | 40,618 | 24% |

### Read this before quoting the savings

**Two things make this refactor much less of a win than it first appears, and both were discovered by
review rather than by the implementation.**

**1. The `inclusion:` frontmatter key decides whether steering is delivered at all, and both of its
documented values break this design.** This was learned the hard way — twice.

All nine files originally carried `inclusion: always`, which injects them into every agent regardless of
any `resources:` list. A review session confirmed it: running as `reviewer`, which declared six files, all
nine arrived. The lists were cosmetic, so the files were switched to `inclusion: manual` on the reasoning
that "manual" meant "by explicit reference only."

It does not. **`inclusion: manual` means never auto-injected, and naming a file in `resources:` does not
count as activation.** For a period every agent therefore received *zero* steering — no pinning rule, no
testing floor, no safety floor — while the lists, the docs, and the checker all said otherwise. Isolated
with a three-way probe: one file with no frontmatter, one `always`, one `manual`, all three named in an
agent's resources. The first two were delivered; the third was not.

**The working state is no `inclusion:` key at all.** The file is then delivered when an agent's
`resources:` names it or a glob matches it. `tools/check-steering-allocation.sh` now fails on *any*
`inclusion:` key and its `--self-test` proves it rejects both values.

The reductions remain contingent on `chat.disableInheritingDefaultResources: true` in `settings/cli.json`,
which is what makes an explicit `resources:` list restrictive rather than additive.

**Verifying delivery at runtime — and the flag that invalidates the test if you forget it.** Start a
session as the agent and ask it to name the steering files it can see:

```bash
kiro-cli --v3 chat --agent docs
```

`--v3` is not optional. Without it the markdown agents do not resolve — the CLI prints
`no agent with name docs found. Falling back to user specified default` and answers as the fallback
agent, so you learn nothing about the agent you asked about. Several rounds of this investigation were
wasted on exactly that.

**Current status of the per-agent counts below: partially verified.** Delivery is confirmed working (an
agent that saw zero files now sees seven). Whether the lists *restrict* precisely to what they declare is
not yet confirmed — `docs` declares five and reported seven. Treat the byte column as the declared
allocation, not a measured one, until that is settled.

**2. Correctness ate most of the saving.** The first version of this allocation dropped more than was
safe. Restoring what agents actually need took `coder` and `ops` back to all nine files — zero reduction
— and took `docs` from 84% down to 24%, because `docs` reads and marks `tasks.md` and the format for that
is defined only in `delivery-workflow.md`, which is 30,338 bytes, over half of all steering.

The honest summary: an implementation agent is subject to nearly every rule in the config, so there is
almost nothing to trim. The real beneficiaries are `security-reviewer` at 28% and `docs` at 24%. Earlier
drafts of this page claimed 84% for `docs` and that "the savings compound across every agent" — both were
wrong, and the second was wrong in a way that would have encouraged trimming further.

### Two files are a floor for every agent

`cli-execution.md` and `artifact-locations.md` are loaded by all six agents regardless of role.

- **`cli-execution.md`** is the *normative* home of the non-interactive execution rules — the MUST-form
  statements, the banned-command table, and the layered-`npx` requirement. Advisory versions of some of
  that guidance also live in `skills/cli-execution/SKILL.md`, which every agent loads via the skill glob,
  so dropping the steering file would not remove the topic entirely — but it would remove the rules as
  *rules*. An agent that hangs on an interactive prompt in an unattended run has broken a MUST, and that
  MUST needs to be in scope for every agent that runs a command.
- **`artifact-locations.md`** governs where workflow artifacts go, and every agent writes one: `coder` and
  `ops` mark tasks in `tasks.md`, `reviewer` writes `review.md`, `security-reviewer` writes
  `security-review.md` and `design-review.md`, `docs` writes into `docs/`. At 1,844 bytes it is the
  cheapest file in the set, and the rule it carries — workflow state under `.kiro/`, never the repo root —
  is the one most easily violated by an agent that cannot see it.

### Corrections to the first allocation, and why

| Change | Reason |
|--------|--------|
| `artifact-locations` added to coder, ops, reviewer, security-reviewer | Absent from all four, yet all four write workflow artifacts. |
| `cli-execution` added to reviewer, security-reviewer, docs | It is the normative form of the non-interactive rules; every agent runs commands. |
| `dependency-versions` added to reviewer, security-reviewer | `security-reviewer`'s own checklist requires verifying "Dependencies pinned to exact versions". Without this file it is asked to enforce a rule it cannot read. |
| `doc-research` added to ops, and to reviewer | `ops` authors IaC and IAM policies and needs the ARN-format and never-infer-an-API rules. `reviewer` needs it to have any gate on them at all. |
| `virtual-environments` added to reviewer | Same argument: a rule whose only reader is the agent expected to comply with it has no independent gate. |
| `documentation` restored to coder and ops | It is the sole home of the docstring requirement, and `ops` is chartered for READMEs, runbooks, and architecture docs. |
| `delivery-workflow` added to docs | `docs` is instructed to read `tasks.md` and mark tasks `[x]`/`[!]`; that format and those semantics are defined only there. It is also the agent on the weakest model tier, least able to infer an unstated convention. |
| `dependency-versions` added to docs | Found by the security review. `docs` is chartered to document dependencies and installation, which is where an unpinned `pip install boto3` gets published — and no hook covers it, since `check-dependency-pins` only inspects manifest-shaped filenames and `check-secrets` skips `.md` entirely. It was the one agent that could publish an unpinned dependency with neither the rule nor a mechanical backstop. |

`virtual-environments` is deliberately **not** loaded by `docs`, and the distinction is worth stating
because the previous row is so close to it. Pinning is a property of the text `docs` writes — a version
number in a quickstart block is either exact or it is not, and the agent needs the rule to get it right.
Choosing an isolation strategy is a property of the project, decided by `coder` or `ops` and already
enforced on them; `docs` describes the setup that exists rather than designing one. If that ever stops
being true — if `docs` starts authoring install procedures rather than documenting them — this is the
first file to add.

`minimalism` is deliberately not loaded by `security-reviewer` — that agent's prompt states code quality
is out of scope. `documentation` is not loaded by either reviewer, since neither is asked to judge
documentation completeness.

Adding a steering file means deciding, in writing, whether the security gate needs it. The glob that
would once have swept it into `security-reviewer` is gone, and `EXPECTED` in
`tools/check-steering-allocation.sh` will actively assert that its absence is correct.

### All five subagents must agree on the path prefix

The subagent lists in this repo use the project-relative form, `file://.kiro/steering/<file>.md`, which
matches the documented install (clone into `<project>/.kiro`). Converting to a global install means
rewriting all five — see [global config](global-config.md).

Get this wrong on one agent and it loads **nothing**. `chat.disableInheritingDefaultResources: true`
makes an explicit list restrictive rather than additive, so an unresolvable list is an empty list, and
an agent with no steering is not an agent with slightly fewer rules — `coder` loses the pinning rule,
the non-interactive rule, the testing floor, and `delivery-workflow.md`, which is where the safety floor and
both mandatory gates live. Nothing reports an error.

This is not hypothetical: two agents in this repo were briefly left on the home-absolute prefix after a
mirror from the maintainer's global config, and `check-steering-allocation.sh` reported them as correct,
because it resolved basenames and discarded the prefix. It now requires all five subagents to use the
same form and fails when one differs. Run it after touching any agent's `resources:`.

### Why the orchestrator keeps globs

1. **Project-level steering must reach it.** A project may ship its own rules in its `.kiro/steering/`.
   The orchestrator is the only agent that reads them; subagents get project constraints restated in
   their task definitions.
2. **An explicit list drifts.** Add a tenth steering file and a glob picks it up; a list silently omits
   it. The orchestrator is the one agent that must see every constraint.

**Consequence:** task quality is the only channel for project-specific rules. If a project has a hard
local constraint and the orchestrator omits it from a task, no subagent will catch it.

## Cost Considerations

A standard-depth feature typically runs:

- **3-4 Opus-tier calls:** architect planning + reviewer + security-reviewer, plus architect fix loops if needed
- **1-2 Sonnet calls:** coder + ops (one or both, depending on the task split)
- **1 Haiku call:** docs agent at the end

Use `prototype` depth to skip the code-review requirement on non-sensitive features. Use `patch` depth for bug fixes: it produces no plan and no task groups, but it still runs both review gates via the `diagnose` flow — the saving is in artifacts, not in scrutiny.

The steering refactor above trims context for two agents and neither implementation agent.
`security-reviewer` drops 28% and `docs` 24%; `reviewer` 3%; `coder` and `ops` nothing at all. It is a smaller
lever than it looks — see *Read this before quoting the savings* above, including the two settings the
reductions depend on.

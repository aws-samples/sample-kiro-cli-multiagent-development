---
name: flywheel
description: Analyze recent session transcripts for user-correction patterns and propose agent/steering/skill configuration improvements. Use when asked to run the flywheel, improve agent configuration, or learn from past sessions.
---

# Flywheel: Agent Configuration Improvement Loop

Analyze recent sessions to identify patterns where the user had to correct, redirect, or steer the agent — then propose configuration changes to prevent recurrence.

Source of truth: the **v3 session transcripts** the engine writes for every session. No separate index
files or hooks are needed — parse the transcripts directly.

## Process

### Phase 1: Session Analysis

1. **Locate recent sessions.** v3 stores each session under `~/.kiro/sessions/<hash>/sess_<uuid>/` with
   two files:
   - `session.json` — metadata: `id`, `title`, `agentMode` (which agent ran), `modelId` (the model),
     `workspacePaths` (cwd), `createdAt`/`lastModifiedAt`, `status`, `description`.
   - `messages.jsonl` — the transcript; one JSON object per line, each with a `payload.type`:
     - `user` → `payload.content` is the user's prompt
     - `assistant` → `payload.content` is the agent's response (`operationType: "Say"` for text)
     - `turn_start` → marks the start of a turn (`executionId`)
     - `session_metadata` → e.g. context-usage samples
   List sessions by `lastModifiedAt` descending; analyze the ~10 most recent (or a date range the user
   specifies).
2. **Scan for correction events** by reading each `messages.jsonl` and examining every `user` message
   (in sequence with the `assistant` messages around it). A correction event is a user message that
   signals the agent did something wrong or suboptimal:
   - **Explicit correction**: "no, I meant…", "that's wrong", "don't do that", "try again but…"
   - **Redirect**: "instead, do…", "I said X not Y", "stop", "cancel that", "start over"
   - **Repeat**: user restating something they already said ("again, but…", "why did you…")
   - **Quality**: "too verbose", "you forgot…", "you missed…"
   - **Tool redirect**: "use X instead", "don't use Y"
   - **Terse**: a very short prompt (< ~60 chars), often a one-word correction
   - **Interrupted turn**: a user message that arrives right after a truncated/short assistant turn
     (the previous turn didn't complete normally), followed by a rephrased request
3. For each correction event, extract:
   - **What the agent did** — the preceding `assistant` message(s) in the same transcript
   - **What the user wanted instead** — the correction message
   - **The underlying principle** — the general rule that would have prevented it
   - **Which agent + model** — from the session's `session.json` (`agentMode`, `modelId`)

### Phase 2: Pattern Recognition

1. Group correction events by theme (e.g., "output too verbose", "wrong tool choice", "ignored
   constraint", "hallucinated API").
2. Filter out one-off mistakes — focus on patterns across 2+ sessions or a clear class of error.
3. **Tag each pattern with the `modelId` that produced it** (read directly from `session.json`). The
   same surface error has different root causes by model — e.g., an implementer agent (`coder`/`ops`)
   going off-plan usually means the *task was under-specified* (fix the `tasks.md` contract or the
   orchestrator that wrote it), whereas a planner (`architect`/`reviewer`/`security-reviewer`)
   doing it points to a prompt/steering gap. Distinguish "the model needed a more literal instruction"
   from "the rule itself is wrong."
4. Classify each pattern as a **steering** issue (universal rule), a **skill** gap (domain knowledge),
   an **agent-config** issue (one agent needs different instructions), or a **task-authoring** issue (an
   implementer was set up to fail by an ambiguous task — fix the upstream orchestrator/task contract).

### Phase 3: Cross-Reference Existing Configuration

1. Read all steering docs: `~/.kiro/steering/*.md`
2. Read all skill docs: `~/.kiro/skills/*/SKILL.md`
3. Read all agent profiles: `~/.kiro/agents/*.md`
4. For each pattern, check: is there already a rule that covers this (and is it too weak/ambiguous)? Is
   there a gap (no rule exists)? Is an existing rule being ignored (needs stronger language/placement)?

### Phase 4: Propose Changes

Present findings as a structured report saved to `~/.kiro/flywheel-report.md`:

```markdown
# Flywheel Report — YYYY-MM-DD

## Sessions Analyzed
- [session title] (date, agent/model) — N correction events found
- ...

## Patterns Identified

### Pattern 1: [descriptive name]
**Frequency**: N occurrences across M sessions
**Model(s)**: [modelId(s) that produced the behavior]
**Examples**:
- Session [title]: user said "..." after agent did "..."
**Root cause**: [why the agent behaved this way]
**Existing coverage**: [which config file addresses this, if any — or "none"]

**Proposed fix**:
- **Type**: steering | skill | agent-config | task-authoring
- **Target**: [file path — new or existing]
- **Change**: [update existing rule | add new rule | add new skill | modify agent profile]
- **Draft content**:
  > [the actual content to add or modify]
```

### Phase 5: Interactive Review

After presenting the report:
1. Walk through each proposed change with the user.
2. For each proposal, ask: **approve, modify, or skip?**
3. For approved changes: show the diff and apply (existing file), or create with proper
   frontmatter/format (new file). Writes to `~/.kiro/{steering,skills,agents}/**` prompt for approval
   (the `permissions.yaml` `ask` rule on `~/.kiro/**`) — that approval *is* the review gate.
4. For modified changes: incorporate feedback and re-present.
5. Summarize all changes made at the end.

## Session Data Format (v3)

Each session lives at `~/.kiro/sessions/<hash>/sess_<uuid>/`:

**`session.json`** — metadata:
```json
{"id":"sess_…","title":"…","agentMode":"architect","modelId":"claude-opus-5",
 "workspacePaths":["/path/to/project"],"createdAt":"…","lastModifiedAt":"…","status":"idle"}
```

**`messages.jsonl`** — transcript, one object per line:
```json
{"timestamp":"…","payload":{"type":"user","content":"no that is wrong, try again differently"}}
{"timestamp":"…","payload":{"type":"turn_start","executionId":"…"}}
{"timestamp":"…","payload":{"type":"assistant","content":"…","operationType":"Say","executionId":"…"}}
```

To analyze: read each `messages.jsonl`, walk events in order, and for every `payload.type == "user"`
evaluate the correction heuristics in Phase 1; when one matches, capture the immediately preceding
`assistant` content as "what the agent did," and read the session's `session.json` for `agentMode`/`modelId`.

> Pre-v3 sessions live under `~/.kiro/sessions/cli/*.jsonl` (a different format) and any historical
> `~/.kiro/flywheel-*.jsonl` index files are no longer maintained — ignore them unless explicitly asked
> to mine old history.

## Rules

- Never fabricate correction events — only report what's actually in the transcripts. Quote the real
  user messages as evidence; don't paraphrase.
- Be conservative: only propose changes for clear, repeated patterns — not every minor hiccup.
- Respect the config hierarchy: steering for universal rules, skills for domain knowledge, agent
  profiles for agent-specific behavior, the `tasks.md` contract for implementer task-authoring.
- New steering docs must include `inclusion: always` frontmatter; new skills must include `name` and
  `description` frontmatter.
- Proposed changes should be minimal and targeted — don't rewrite entire files. If a pattern is already
  covered, strengthen the existing rule rather than adding a duplicate.

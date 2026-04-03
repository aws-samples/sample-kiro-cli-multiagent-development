# Flywheel: Agent Configuration Improvement Loop

Analyze recent sessions to identify patterns where the user had to correct, redirect, or steer the agent — then propose configuration changes to prevent recurrence.

## Process

### Phase 1: Session Analysis

1. Check for the flywheel hook log at `~/.kiro/flywheel-log.jsonl` — if present, read it first for a pre-filtered view of recent agent responses (faster than parsing full session JSONL)
2. Read all session metadata files (`~/.kiro/sessions/cli/*.json`) to get session list, sorted by `updated_at` descending
3. For each session (most recent first, up to 10 sessions), read the `.jsonl` conversation log
4. Identify **correction events** — user messages that indicate the agent did something wrong or suboptimal:
   - Explicit corrections: "no, I meant...", "that's wrong", "don't do that", "try again but..."
   - Redirections: "instead, do...", "I said X not Y", "stop", "cancel that"
   - Repeated instructions: user restating something they already said
   - Frustration signals: user simplifying their request after a failed attempt
   - Cancelled turns (`end_reason: "Cancelled"`) followed by a rephrased request
   - Tool failures that required user intervention to resolve
   - Agent making assumptions the user had to correct
4. For each correction event, extract:
   - What the agent did wrong (the assistant message before the correction)
   - What the user wanted instead (the correction message)
   - The underlying principle (what general rule would have prevented this)
   - Which agent was running (`agent_name` from session metadata)

### Phase 2: Pattern Recognition

1. Group correction events by theme (e.g., "output too verbose", "wrong tool choice", "ignored constraint", "hallucinated API")
2. Filter out one-off mistakes — focus on patterns that appear across 2+ sessions or represent a class of error
3. For each pattern, determine if it's:
   - A **steering** issue (general behavioral rule that applies to all agents)
   - A **skill** gap (domain-specific knowledge the agent is missing)
   - An **agent** config issue (specific agent needs different instructions or constraints)

### Phase 3: Cross-Reference Existing Configuration

1. Read all steering docs: `~/.kiro/steering/*.md`
2. Read all skill docs: `~/.kiro/skills/*/SKILL.md`
3. Read all agent prompts: `~/.kiro/agents/*.md`
4. For each identified pattern, check:
   - Is there already a rule that covers this? → If yes, is it too weak or ambiguous?
   - Is there a gap — no rule exists for this class of error?
   - Is an existing rule being ignored? → May need stronger language or a different placement

### Phase 4: Propose Changes

Present findings as a structured report saved to `~/.kiro/flywheel-report.md`:

```markdown
# Flywheel Report — YYYY-MM-DD

## Sessions Analyzed
- [session title] (date) — N correction events found
- ...

## Patterns Identified

### Pattern 1: [descriptive name]
**Frequency**: N occurrences across M sessions
**Examples**:
- Session [title]: user said "..." after agent did "..."
- Session [title]: user said "..." after agent did "..."
**Root cause**: [why the agent behaved this way]
**Existing coverage**: [which config file addresses this, if any — or "none"]

**Proposed fix**:
- **Type**: steering | skill | agent-config
- **Target**: [file path — new or existing]
- **Change**: [update existing rule | add new rule | add new skill | modify agent prompt]
- **Draft content**:
  > [the actual content to add or modify]
```

### Phase 5: Interactive Review

After presenting the report:
1. Walk through each proposed change with the user
2. For each proposal, ask: **approve, modify, or skip?**
3. For approved changes:
   - If updating an existing file: show the diff and apply
   - If creating a new file: create it with proper frontmatter/format
   - Note: if the `config-drift-guard.sh` hook is active, writes to steering/skills/agents will be blocked until the user approves. This is by design — the hook enforces the review step.
4. For modified changes: incorporate feedback and re-present
5. Summarize all changes made at the end

## Session Data Format

### Flywheel Hook Log (preferred — fast path)

If the `flywheel-log.sh` stop hook is configured, it writes lightweight turn summaries to `~/.kiro/flywheel-log.jsonl`:

```json
{"timestamp": "2026-04-02T19:16:54Z", "cwd": "/path/to/project", "response_length": 1234, "response_preview": "first 500 chars..."}
```

This log provides a quick index of recent activity. Use it to identify which sessions are worth deep-diving into, then read the full session JSONL for correction event details.

### Full Session Data

Kiro stores sessions in `~/.kiro/sessions/cli/` with two files per session:

- `<uuid>.json` — metadata including `session_id`, `created_at`, `updated_at`, `title`, `agent_name`, and per-turn stats (turn count, duration, end reason)
- `<uuid>.jsonl` — conversation log where each line is a typed event:
  - `{"kind": "Prompt", "data": {"content": [{"kind": "text", "data": "..."}]}}` — user messages
  - `{"kind": "AssistantMessage", "data": {"content": [...]}}` — agent responses (text + tool uses)
  - `{"kind": "ToolResults", "data": {"content": [...]}}` — tool execution results

Key metadata fields for correction detection:
- `end_reason: "Cancelled"` — user interrupted the agent mid-turn
- `end_reason: "UserTurnEnd"` — normal turn completion
- `total_request_count` and `number_of_cycles` — high values may indicate the agent was struggling

## Rules

- Never fabricate correction events — only report what's actually in the session logs
- Be conservative: only propose changes for clear, repeated patterns — not every minor hiccup
- Respect the existing config hierarchy: steering for universal rules, skills for domain knowledge, agent prompts for agent-specific behavior
- New steering docs must include `inclusion: always` frontmatter
- New skill docs must include `name` and `description` frontmatter
- Proposed changes should be minimal and targeted — don't rewrite entire files
- If a pattern is already covered by an existing rule, propose strengthening the language rather than adding a duplicate
- Quote the actual user messages as evidence — don't paraphrase

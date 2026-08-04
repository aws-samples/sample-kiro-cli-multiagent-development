# Observability & Debugging

## Session Transcripts

Every Kiro CLI v3 session writes a transcript to:

```
~/.kiro/sessions/<hash>/sess_<uuid>/messages.jsonl
```

Each line is a JSON object representing one message in the conversation: user prompts, assistant
responses, tool calls, tool results, and system events. The transcript is append-only during a session
and never modified after the session ends.

> **Do not use `~/.kiro/sessions/cli/`.** That directory holds flat pre-v3 `<uuid>.json` / `.jsonl`
> files in a different format. On a v3 install it matches none of the current transcripts.

To read a transcript:

```bash
# Find recent sessions (newest last)
ls -lt ~/.kiro/sessions/*/sess_*/messages.jsonl | head

# Pretty-print the most recent session
jq . "$(ls -t ~/.kiro/sessions/*/sess_*/messages.jsonl | head -1)"

# Filter to user messages only
jq 'select(.role == "user")' "$(ls -t ~/.kiro/sessions/*/sess_*/messages.jsonl | head -1)"
```

Message objects carry `role`, `content`, and a timestamp. Token accounting is present but its exact
shape is not stable across releases — inspect one line before writing a query against it:

```bash
jq -c 'keys' "$(ls -t ~/.kiro/sessions/*/sess_*/messages.jsonl | head -1)" | sort -u
```

## Monitoring Subagents

When the orchestrator spawns subagents via `/spawn`, you can monitor their execution:

- **Ctrl+G** opens the agent monitor (all running and completed subagents)
- **Ctrl+X** opens the activity tray

The monitor shows each subagent's status, its assigned task, and a rolling view of its output. Other
keybindings vary by CLI version — check the in-TUI help rather than relying on this page.

## Failure Modes

### A spawned subagent fails

The task contract requires the subagent itself to stop rather than loop: if its `Verify` command fails
twice for the same reason, it marks the task `[!]` with the exact error and stops. The orchestrator then
sees an unfinished group and decides whether to create a fix task or escalate. The stop rule belongs to
the subagent, not to an auto-respawn loop in the orchestrator — there is no automatic retry.

### A review gate keeps failing

Each gate is capped at **3 cycles**. If a gate still returns FAIL after the third cycle, the workflow
**halts and escalates to you** with a summary of the unresolved findings. It does not annotate the
finding and continue — an unresolved Critical or Warning blocks completion by definition, since the
completion criteria require zero of both.

### File conflicts from parallel agents

Rare by design: the orchestrator assigns tasks with disjoint file sets to parallel subagents. If it
happens anyway — usually from an overly broad task — the review gate catches the inconsistency and it
becomes a fix task.

## Cost Visibility

Kiro CLI shows token usage per session in the TUI. Enable the context indicator with:

```bash
kiro-cli settings chat.enableContextUsageIndicator true
```

For per-session aggregation, parse the transcript — but confirm the token field shape first with the
`jq -c 'keys'` command above, since it is not formally versioned.

Periodic [flywheel](flywheel.md) runs are the practical cost control: if sessions consistently burn
tokens on research, that is a signal a steering rule or skill needs tightening.

## Current Gaps

- No aggregate dashboard across sessions — you parse transcripts yourself
- No cost-per-feature rollup; tokens are tracked per session, not per plan
- No built-in comparison of token usage across depth levels
- The transcript format is not formally versioned and may change between CLI releases
- Gate escalation is visible only when it happens; there is no proactive alert as cycles accumulate

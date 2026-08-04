# The Flywheel (Self-Improvement Loop)

The system learns from your corrections. Every redirect ("no, use X instead", "try again but...", "stop, do it this way") is a signal.

## The Loop

```
Sessions ──▶ Corrections ──▶ Patterns ──▶ Config changes
    ▲                                         │
    └──────────── better behavior ────────────┘
```

Each cycle tightens the system. Corrections become patterns. Patterns become steering rules, skill updates, or agent prompt changes. Those changes prevent the same mistake from recurring in future sessions.

## How It Works

The flywheel runs in five phases:

1. **Session analysis** scans recent session transcripts for correction events: user messages that redirect, override, or contradict the agent's previous action.

2. **Pattern recognition** groups corrections by theme and filters out one-offs. A single correction might be situational; three corrections about the same behavior indicate a gap.

3. **Cross-reference** checks existing steering docs, skills, and agent prompts for coverage gaps. If a steering rule already addresses the pattern, the flywheel notes that the rule is not being followed (prompt reinforcement needed) rather than proposing a new rule.

4. **Propose changes** writes a structured report with evidence (session excerpts) and draft config content (new steering paragraphs, skill additions, or prompt edits).

5. **Interactive review** walks through each proposal for your approval before applying. You accept, modify, or reject each change individually.

## What It Reads

The flywheel reads v3 session transcripts directly:

```
~/.kiro/sessions/*/sess_*/messages.jsonl
```

It scans user messages for correction signals and the surrounding assistant turns for context. No logging hooks are required; the engine writes the transcript for every session automatically.

## Invoking

```bash
kiro-cli --v3 chat
# then type:
/flywheel
```

Run it after a few sessions of active work, especially sessions where you corrected the agent multiple times. Running it on a single correction rarely produces useful patterns.

## Why This Matters

Single-agent workflows forget between sessions. You correct the same mistake repeatedly because nothing encodes the lesson. The flywheel closes that gap: it turns ephemeral corrections into durable configuration so the same mistake does not recur.

The cost of running the flywheel is one Opus-tier session (it needs judgment to distinguish real patterns from noise). The return is fewer corrections in every subsequent session.

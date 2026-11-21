---
type: Task
description: A pipeline that turns finished agent sessions into short, deduplicated and discoverable knowledge and skills, running only on the local model fleet.
status: open
authored_by: agent
timestamp: 2026-11-21T23:10:00+01:00
---

# Distil sessions into knowledge and skills

## Context

Every harness session leaves a transcript. The useful part — the decisions, the pitfalls, the
commands that worked — stays buried in it. A human who reads the transcript once learns it; the
next session does not. The bundle at `.agents/knowledge` holds only the few concepts somebody wrote
by hand.

The local fleet is ready: `brys` serves 24-35B models at 20-23 t/s with a 32k window, plus an
embedding and a reranking model. Extraction and merging are mechanical, well-specified work, so
they fit the smaller slots.

## Goal

One command reads sessions, extracts durable items, merges the repeats, and proposes:

1. **knowledge concepts** (decisions, runbooks, pitfalls, preferences, facts) for
   `.agents/knowledge`;
2. **skill drafts** when the same procedure appears in three or more sessions;
3. **contradictions**, when a new item disagrees with an existing concept.

Nothing enters the bundle without a review step. A proposal is a directory a human can read, and
`apply` is a separate command.

## Constraints

- **Local models only.** No request may leave the local fleet. The client refuses an endpoint that
  is not on an explicit allow-list.
- **Resumable.** A run over 570 sessions takes hours. It must survive a dropped connection and
  continue from the last finished session.
- **Deterministic where possible.** Deduplication and clustering use lexical similarity, not a
  model, so a re-run produces the same clusters.
- **One writer.** The bundle has one writer (`okf-agent-memory`). The pipeline writes a proposal and
  hands it over; it does not fight the bundle owner.
- **Remote use.** It must run from a laptop in another city over NetBird, against the endpoint on
  `brys`.

## Acceptance

- `kdn-knowledge run` over the real OpenCode database produces a proposal directory in under an
  hour on the local fleet, with a report of what it read, what it extracted and what it merged.
- A second run over the same input extracts nothing new (idempotent by content hash).
- The proposal validates with `kdn-okf` / `okflint` before `apply` touches the bundle.
- The endpoint guard refuses `https://api.openai.com` and any other non-local host.

## Out of scope

- Rewriting the bundle in place without review.
- Reading images, audio or video.
- Training or fine-tuning.

---
type: Design
description: The command surface, the on-disk layout, the JSON contracts and the model prompts of kdn-knowledge, a session-to-knowledge pipeline that runs only on the local fleet.
timestamp: 2026-11-21T23:15:00+01:00
---

# kdn-knowledge — design

## Why a separate binary

The pipeline is a durable tool: it runs unattended, it is resumed, and it must work from a laptop
over NetBird. A static Go binary with no third-party dependency satisfies all three. It reads
SQLite through the `sqlite3` CLI (stdlib has no driver) and speaks JSON over HTTP with
`net/http`.

## Command surface

```
kdn-knowledge harvest [--db PATH] [--since DATE] [--project DIR] [--limit N]
kdn-knowledge extract [--model ID] [--limit N] [--force] [--dry-run]
kdn-knowledge dream   [--threshold F] [--min-sessions N]
kdn-knowledge apply   [--proposal DIR] [--yes]
kdn-knowledge run     [--limit N] [--model ID]
kdn-knowledge status
```

`run` is `harvest` → `extract` → `dream`, and stops before `apply`.

Every command prints a one-line summary to stdout and progress to stderr. `--json` puts the
summary on stdout as one object.

## On-disk layout

Base directory: `${XDG_CACHE_HOME:-~/.cache}/kdn/knowledge`, overridden by `--data-dir` or
`KDN_KNOWLEDGE_DATA`.

```
corpus/<session-id>.json           one normalised session
candidates/<session-id>.json       extracted items for that session
state.json                         session id -> content hash, status, attempts
proposals/<UTC timestamp>/
  concepts/<id>.md                 OKF concept drafts
  skills/<slug>.md                 skill drafts
  plan.json                        machine-readable actions
  report.md                        what the run read, found and merged
runs/<UTC timestamp>.log           stderr log of the run
```

## Corpus record

```json
{
  "id": "ses_...",
  "source": "opencode",
  "title": "...",
  "directory": "/home/kdn/dev/github.com/nazarewk-iac/nix-configs",
  "started": "2026-11-21T20:00:00Z",
  "messages": [
    {"role": "user", "text": "..."},
    {"role": "assistant", "text": "..."},
    {"role": "tool", "name": "bash", "text": "..."}
  ],
  "hash": "sha256:..."
}
```

The hash covers the concatenated role and text of every message, so an edited session is
extracted again and an unchanged one is skipped. Reasoning parts are dropped: they are long, and
they are not knowledge.

## Candidate item

```json
{
  "session": "ses_...",
  "kind": "decision|runbook|pitfall|preference|fact",
  "statement": "one or two sentences, imperative or declarative",
  "tags": ["jj", "nix"],
  "confidence": "high|medium|low",
  "evidence": ["2026-11-21T20:03:00Z"]
}
```

The model returns a JSON array of items and nothing else. A reply that is not valid JSON gets one
repair attempt with the parser error appended; a second failure records the session as `failed`
with the reason, and the run continues.

## Extraction prompt (fixed text, in `prompt.go`)

System:

> You extract durable engineering knowledge from an agent session. Reply with a JSON array only.
> Each item is `{"kind","statement","tags","confidence","evidence"}`. Keep an item only if it
> would still be true and useful in a different session next month. Drop chatter, plans, status
> reports, restatements of the user's request, and anything that names a temporary path, port or
> commit id. Prefer five good items over thirty weak ones. If the session carries nothing
> durable, reply with `[]`.

User message: the session title, its date, and the transcript with `user:` / `assistant:` /
`tool(name):` prefixes.

Chunking: a session longer than 24000 characters is split on message boundaries into chunks of at
most 24000 characters with one message of overlap. Each chunk is one call. Items from all chunks
are concatenated and deduplicated by statement similarity before they are written.

## Dream

1. Load every `candidates/*.json`.
2. Group by `kind`.
3. Similarity: Jaccard over the set of lowercased word trigrams of `statement`, plus 0.1 when the
   tags intersect. Two items join a cluster when similarity ≥ `--threshold` (default 0.45).
4. A cluster with one item and `confidence: low` is dropped.
5. A cluster with two or more items gets one model call: merge into one statement of at most two
   sentences that keeps every distinct fact, and return `{"statement": "...", "tags": [...]}`.
   The merged item inherits the union of evidence and the highest confidence.
6. Compare each merged item with the existing concepts under `.agents/knowledge` (parse the
   frontmatter `id`, `title`, `description`, and the first paragraph). Similarity uses the same
   metric against `title + description`.
7. Action per item: `new` (no match), `update` (similarity ≥ 0.7, same kind), `conflict`
   (similarity ≥ 0.7 but the model answers "contradicts" when asked to compare the two statements).
8. **Skill distillation**: a cluster with `kind: runbook`, at least `--min-sessions` distinct
   sessions and at least three ordered command-like lines in its evidence becomes a skill draft.

## Proposal and apply

`proposals/<timestamp>/concepts/<id>.md` uses the bundle's frontmatter:

```yaml
---
type: Decision
title: ...
description: ...
generated: { by: agent/kdn-knowledge, at: "..." }
status: draft
id: <slug>
links: []
---
```

`plan.json` lists every action with its target id and the concept file. `report.md` is the human
summary: sessions read, items extracted, clusters merged, actions by type, and every failed
session with its reason.

`apply --yes` copies the concept files into `.agents/knowledge/<type-dir>/`, refuses to overwrite a
concept whose `status` is `stable`, and then runs `kdn-okf doctor --parse-only` when that binary is
on `PATH`. A validation error rolls the copied files back.

## Endpoint guard

The endpoint must pass `guardEndpoint` before the first request:

- allowed hosts: `localhost`, `127.0.0.1`, `::1`, any host ending in `.nb.net.int.kdn.im`, and the
  names in `--allow-host` (repeatable);
- allowed schemes: `http`, `https`;
- any other host is refused with a message that names it and the flag that would allow it.

This is the "local models only" guarantee. A test covers `api.openai.com` and a look-alike
`brys.priv.nb.net.int.kdn.im.evil.example`.

## Defaults

| knob | default |
| --- | --- |
| endpoint | `https://llama-swap.brys.priv.nb.net.int.kdn.im/v1` |
| extract model | `lfm2.5-24b-a2b` |
| merge model | `nemotron-3-nano-30b-a3b` |
| request timeout | 300 s per call |
| retries | 1 repair attempt, then fail the session |
| sessions db | `~/.local/share/opencode/opencode.db` |
| project filter | the current directory |

The defaults name base model ids, not purpose aliases: several aliases in `data/llm.nix` still
point at models that were pruned from the catalogue, and a missing alias answers
`no router for requested model`. `status` prints the resolved model and endpoint so a stale
default is visible.

## Serving reality

The frontier rests on `max-multi` (512k × 5), which leaves about 8 GiB of VRAM. A 24B extractor may
not fit beside it. `status` therefore asks the manager:

```
POST http://<host>:8181/decide  {"model":"lfm2.5-24b-a2b","resident":[]}
```

and prints the verdict, the refusing check and the alternatives. `extract` prints the same verdict
once before the first call, so a run that cannot load its model fails at the start and not after
two hundred sessions.

Two configurations are supported:

| configuration | extract model | when |
| --- | --- | --- |
| beside the resting frontier | `gemma-4-e4b` or `ministral-3-3b-reasoning` | a normal evening run |
| colo profile | `lfm2.5-24b-a2b` | a long night run; switch with `strata-select --profile qfn-max-colo` first |

The tool does not switch profiles by itself: a switch stops the engine and would cut somebody
else's session.

## Failure handling

- A model error, a timeout or invalid JSON marks that session `failed` in `state.json` with the
  reason and the attempt count; the run continues.
- A second `extract` retries only `failed` and `new` sessions.
- `harvest` never deletes a corpus file; a session removed from the database keeps its corpus and
  is marked `orphaned` in `state.json`.

## Tests

- `harvest` against a fixture SQLite database with two sessions, one with tool parts.
- `extract` against a fake HTTP server: valid JSON, invalid JSON then repair, and a timeout.
- `dream` clustering with fixed items: two near-duplicates merge, one unrelated item does not.
- `guardEndpoint` table test.
- `state` resume: an unchanged hash skips, a changed hash re-extracts.

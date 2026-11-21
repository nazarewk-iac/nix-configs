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
    { "role": "user", "text": "..." },
    { "role": "assistant", "text": "..." },
    { "role": "tool", "name": "bash", "text": "..." }
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

Chunking: **off by default**. The default model is the frontier engine (`qfn`) with a 512k window, so a
whole session fits. Chunking is opt-in (`--chunk-chars 24000`) for a smaller model: it splits on
message boundaries with one message of overlap, and items from all chunks are concatenated and
deduplicated before they are written.

The frontier is a reasoning model. Every request carries
`chat_template_kwargs: {"enable_thinking": false}`; without it the reply puts everything in
`reasoning_content` and `content` is empty.

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

| knob            | default                                             |
| --------------- | --------------------------------------------------- |
| endpoint        | `https://llama-swap.brys.priv.nb.net.int.kdn.im/v1` |
| api key file    | `/run/configs/llms/llama-server/api-keys/default`   |
| extract model   | `qfn` (the frontier engine, always loaded)          |
| merge model     | `qfn`                                               |
| request timeout | 300 s per call                                      |
| retries         | 1 repair attempt, then fail the session             |
| sessions db     | `~/.local/share/opencode/opencode.db`               |
| project filter  | the current directory                               |

The defaults name base model ids, not purpose aliases: several aliases in `data/llm.nix` still
point at models that were pruned from the catalogue, and a missing alias answers
`no router for requested model`. `status` prints the resolved model and endpoint so a stale
default is visible. Every request sends `Authorization: Bearer <key>` and
`chat_template_kwargs: {"enable_thinking": false}`.

## Serving reality

The frontier rests on `max-multi` (512k × 5) and **answers every request**: it never unloads, so it
is the default extractor. The endpoint needs a bearer key, read from
`/run/configs/llms/llama-server/api-keys/default` (world-readable on oams and on brys; a symlink
into `/run/secrets`).

A llama.cpp grunt model is **not** an option on the resting profile. `gemma-4-e4b` and
`ministral-3-3b-reasoning` both fail to start beside `max-multi`: `admit` refuses them, and
llama-swap answers `upstream command exited prematurely`. They work on a colo profile
(`omni-fast`, `omni-max`), which costs a 58–74 s switch and takes the card from every other
session.

`status` therefore asks the manager:

```
POST http://brys:8181/decide  {"model":"qfn"}
```

and prints the verdict and the refusing check. A `429 a switch just happened; retry shortly` is the
30 s cooldown, not a capacity problem.

| configuration                | extract model                   | when                                               |
| ---------------------------- | ------------------------------- | -------------------------------------------------- |
| resting profile, recommended | `qfn`                           | any time; the engine is already loaded             |
| colo profile                 | `gemma-4-e4b`, `lfm2.5-24b-a2b` | a long night run that must leave the frontier free |
| no GPU                       | `gemma-4-e4b` on `omni-fast`    | the user is not using the frontier                 |

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

## Implementation notes

The build follows this design. The items below record the choices that the design left open, and
the two places where the real fleet forced a change. The binary and the tests are the source of
truth.

1. **The prompt names the five kinds.** The fixed text did not list the vocabulary, so the model
   labelled every item `fact` and a runbook cluster could never form. One line now reads
   `"kind" is one of: decision, runbook, pitfall, preference, fact.` The rest of the wording is
   unchanged. Measured effect on the same eight sessions: 5 decision, 12 pitfall, 7 runbook,
   5 preference, 11 fact.
2. **A title is a phrase.** The title is the first sentence, capped at 72 characters at the last
   word boundary. Trailing `,;:` and an unmatched backtick are removed, and a trailing hyphenated
   compound modifier is dropped (`… maintain a session-level` becomes `… must maintain`). A title
   that the cap shortened ends with `…`, so a cut stays visible. The id comes from the first eight
   significant words of that sentence, not from the title.
3. **A skill is the repeated step.** Skill steps are the commands that at least two sessions of
   the cluster ran, in first-seen order, capped at 12. The rule is lexical, not semantic: a later
   pass can distil the steps with the model.
4. **The candidate file is an envelope.** `candidates/<session>.json` is
   `{"session","model","extracted_at","truncated","items"}`. The item shape is unchanged.
5. **A tool message can carry its command.** A corpus message gains `command` for a tool part that
   holds a shell command. Skill distillation reads it; the hash covers it.
6. **A running session is not extracted.** OpenCode marks a finished session with `time_idle`.
   `harvest` skips a session that has none, because its transcript still grows. `--include-live`
   opts in.
7. **Two sources.** `harvest --source all|opencode|pi` reads both stores; `--pi-root` defaults to
   `~/.pi/agent/sessions`. A Pi session with no user or assistant text is skipped silently, and a
   malformed line is counted and skipped. The project comes from the header `cwd`. `status`
   prints the session count per source.
8. **The manager check is opt-in.** `--manager` is empty by default: from a laptop the check only
   spends the timeout. On `brys`, pass `--manager http://127.0.0.1:8181`. A `429` is the
   post-switch cooldown, not a refusal. `extract` and `status` print `decide: skipped` when the
   flag is absent.
9. **`apply` uses the bundle writer.** When `okf-memory` is on `PATH`, `apply` calls
   `okf-memory create|update` with `--status draft` and `--actor agent/kdn-knowledge`, so `log.md`
   and the parent `index.md` stay correct, then gates the bundle with
   `okflint validate --manifest <bundle>/okf-base.yaml <bundle>`. A validation error removes the
   concepts just created and restores the bookkeeping files. Direct file writing is only the
   fallback, and it warns that the log and index were not updated. Skill drafts are not concepts,
   so `apply` leaves them in the proposal.
10. **The estimate is measured, not guessed.** `extract` prints the running average and the
    estimate for the sessions that remain. `status` prints the same estimate from the finished
    sessions in `state.json` (the `seconds` field).
11. **Chunking is off unless asked for.** `--chunk-chars N` splits on message boundaries with one
    message of overlap. A transcript above 1.5 million characters fails fast with a message that
    names the flag, instead of a server-side context error.
12. **The endpoint contract.** Every request sends `Authorization: Bearer <key>` from
    `--key-file` (default `/run/configs/llms/llama-server/api-keys/default`) and
    `chat_template_kwargs: {"enable_thinking": false}`, `temperature: 0`, `max_tokens: 2048`.

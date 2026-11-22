---
type: README
description: kdn-knowledge turns finished agent sessions into short, deduplicated knowledge and skill proposals for the agent memory bundle, using only the local model fleet.
timestamp: 2026-11-22T04:45:00+01:00
---

# kdn-knowledge

A pipeline that reads harness sessions, extracts the durable parts, merges the repeats, and
proposes concepts for `.agents/knowledge`. It runs on the local fleet: the model is `qfn` on
`brys`, and an endpoint guard refuses any host outside the private network.

Nothing enters the bundle without review. A run writes a **proposal directory**; `apply` is a
separate command with its own gates.

## The shape

```
   OpenCode DB ─┐
                ├─► harvest ──► corpus/<session>.json
   Pi JSONL ────┘                     │
                                      ▼
                              extract  (qfn, strict JSON) ──► candidates/<session>.json
                                      │
                                      ▼
                              dream    (deterministic clustering + one merge call per cluster)
                                      │
                                      ├─► concepts/<id>.md     OKF drafts, status: draft
                                      ├─► skills/<slug>.md     when a runbook repeats
                                      ├─► plan.json            new / update / conflict, not_proposed
                                      └─► report.md            the human summary
                                      │
                                      ▼
                              apply --yes  (okf-memory create → id → canon → okflint → ai-xf)
                                      │
                                      ▼
                              .agents/knowledge/**
```

## The four stages

| stage     | reads                                                            | does                                                                                                                                                  | writes                      |
| --------- | ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| `harvest` | `~/.local/share/opencode/opencode.db`, `~/.pi/agent/sessions/**` | normalises each session, drops reasoning and system prompts, truncates tool output to 2 000 characters, hashes the transcript                         | `corpus/<session>.json`     |
| `extract` | `corpus/`                                                        | one `qfn` call per session with a fixed prompt and a JSON contract; one repair attempt, then the session is marked `failed`                           | `candidates/<session>.json` |
| `dream`   | `candidates/` + the existing bundle                              | clusters by lexical similarity, merges each cluster with one model call, compares with existing concepts, ranks and caps the proposal, distils skills | `proposals/<ts>/`           |
| `apply`   | one proposal                                                     | writes through the bundle writer, completes the `id`, runs three gates, rolls back on failure                                                         | `.agents/knowledge/`        |

`run` is `harvest` → `extract` → `dream` and stops before `apply`.

## The data model

Four JSON shapes carry the whole pipeline. Each one is a file, so a run can be inspected and
resumed by hand.

**Corpus record** — `corpus/<session>.json`:

```json
{
  "id": "ses_…",
  "source": "opencode|pi",
  "title": "…",
  "directory": "/home/kdn/dev/…",
  "started": "2026-11-21T20:00:00Z",
  "messages": [
    { "role": "user", "text": "…" },
    { "role": "assistant", "text": "…" },
    { "role": "tool", "name": "bash", "text": "…" }
  ],
  "hash": "sha256:…"
}
```

**Candidate item** — one element of `candidates/<session>.json`:

```json
{
  "session": "ses_…",
  "kind": "decision|runbook|pitfall|preference|fact",
  "statement": "one or two sentences",
  "tags": ["jj", "nix"],
  "confidence": "high|medium|low",
  "evidence": ["2026-11-21T20:03:00Z"]
}
```

**Plan** — `plan.json`: `actions` (each `new`, `update` or `conflict`), `not_proposed` (the
clusters over the cap, one line each), `skills`, `cluster_summaries`, `failures`, and the counts.

**Concept draft** — `concepts/<id>.md`: OKF frontmatter (`type`, `title`, `description`,
`generated`, `status: draft`, `id`, `tags`, `links`) plus a body, an `## Evidence` list and a
`> Draft from kdn-knowledge` footer.

## On-disk layout

Base directory `${XDG_CACHE_HOME:-~/.cache}/kdn/knowledge` (`--data-dir`):

```
corpus/<session>.json          one normalised session
candidates/<session>.json      its extracted items (an empty list is a success)
state.json                     session id → hash, status, attempts, reason, seconds
proposals/<ts>/                concepts/ skills/ plan.json report.md
runs/<ts>.log                  the stderr log of one run
```

## The package map

| package             | responsibility                                                                                    |
| ------------------- | ------------------------------------------------------------------------------------------------- |
| `internal/harvest`  | walks both stores, applies the filters, writes corpus records, marks vanished sessions `orphaned` |
| `internal/corpus`   | the OpenCode reader: `sqlite3 -json` over `session_v2` + `session_message`                        |
| `internal/pi`       | the Pi reader: one JSONL file per session, header `cwd`, `message` events                         |
| `internal/llm`      | the OpenAI-compatible client, the bearer key, the JSON repair, the `/decide` probe                |
| `internal/guard`    | the endpoint allow-list — the "local models only" rule                                            |
| `internal/extract`  | the prompt, the item parser, the per-session call                                                 |
| `internal/dream`    | clustering, merge, comparison with the bundle, ranking, the cap, skill distillation               |
| `internal/textsim`  | deterministic trigram similarity and tag overlap — no model, no map order                         |
| `internal/bundle`   | reads the existing concepts; never writes                                                         |
| `internal/okfkind`  | the one table that maps the five kinds to OKF types and directories                               |
| `internal/proposal` | writes the reviewable directory                                                                   |
| `internal/apply`    | the writer hand-off, the `id` completion, the three gates, the rollback                           |
| `internal/state`    | the resumable ledger, rewritten atomically after every session                                    |
| `internal/store`    | the layout; every write is a temp file plus a rename                                              |
| `internal/pipeline` | the two steps that touch both the store and the ledger                                            |

## The model contract

- **Endpoint** `https://llama-swap.brys.priv.nb.net.int.kdn.im/v1`, which resolves to brys over
  NetBird, so a laptop in another city uses the same command.
- **Key** `/run/configs/llms/llama-server/api-keys/default` (`--key-file`,
  `KDN_KNOWLEDGE_KEY_FILE`), sent as `Authorization: Bearer`.
- **Model** `qfn`, the frontier engine that is already loaded: nothing switches and nothing
  unloads. A llama.cpp grunt model is refused on the resting profile, so it is not a default.
- **Request** `temperature: 0`, `max_tokens: 2048`,
  `chat_template_kwargs: {"enable_thinking": false}`. Without the last field the frontier puts the
  answer in `reasoning_content` and `content` is empty.
- **Reply** a JSON array of items. The parser accepts `confidence` as a number, a numeric string or
  a level, and `evidence` as a string or an array, because the model does not always obey the types.

## Determinism, resume and failure

- The transcript **hash** decides what to extract. An unchanged session is skipped; `--force`
  re-extracts.
- `state.json` is rewritten after every session, so a kill loses at most the session in flight.
  `extract` retries `failed` sessions on its own.
- Clustering, ranking and the over-cap list are sorted, so two runs over the same candidates give
  the same plan. Only a model-merged statement can differ in wording.
- A session that is longer than the window fails with a reason and the fix
  (`--chunk-chars 24000`), rather than being silently truncated.
- A session with nothing durable returns `[]` and produces an empty candidate file. That is a
  success, not a failure.

## The gates

`apply --yes` writes through `okf-memory create` so `log.md` and the directory `index.md` stay
correct, completes the one field the writer omits (`id`), then runs, in order:

1. `ai-xf-canon check` (rewriting non-canonical files),
2. `okflint validate --manifest .agents/knowledge/okf-base.yaml .agents/knowledge`,
3. `ai-xf-validate .agents/knowledge --level 2`.

A missing binary is a printed warning. A failing gate deletes the concepts this run created,
restores the bookkeeping files, and exits non-zero. A concept whose status is `stable` is never
overwritten.

## Guards

- The endpoint must pass the allow-list: loopback, `*.nb.net.int.kdn.im`, and whatever
  `--allow-host` adds. `api.openai.com` and look-alike names are refused before the first request.
- The tool never switches a profile and never unloads a model.
- The bundle has one writer. `apply` hands every concept to it; the pipeline never edits `index.md`
  or `log.md` itself.

## Extending it

- **A new harness**: add a reader beside `internal/pi`, emit the same corpus record, and add it to
  the `--source` switch. Nothing downstream changes.
- **A new kind**: add it to `internal/okfkind` and to the manifest types in
  `.agents/knowledge/okf-base.yaml`. One table drives the writer, the reader and the applier.
- **A different model**: `--model` and `--merge-model`. Use a base id, not a purpose alias: an
  alias whose model was pruned answers `no router for requested model`.

## Documentation

- Runbook and measured costs: [docs/knowledge-pipeline.md](../../docs/knowledge-pipeline.md).
- Design and the choices it forced:
  [docs/tasks/2026-11/knowledge-pipeline/design.md](../../docs/tasks/2026-11/knowledge-pipeline/design.md).
- The task: [docs/tasks/2026-11/knowledge-pipeline/definition.md](../../docs/tasks/2026-11/knowledge-pipeline/definition.md).
- The bundle it feeds: [docs/okf-memory.md](../../docs/okf-memory.md).

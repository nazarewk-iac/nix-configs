---
type: Task
description: A minimal, general-purpose local retrieval index (RAG) over documents, notes and jj history, with a small embedding model, a single embedded store, and Pi tools for search and fetch.
status: open
authored_by: agent
timestamp: 2026-11-03T11:47:41+01:00
---

# Local retrieval index for documents, notes and jj history

## Context

Session reading is exact and deterministic (`session_list`/`session_grep`/`session_digest`/
`session_detail`). It does not help when the target is not a session: a note, a document, or a
past change to a file. That needs approximate retrieval over a corpus.

A cross-checked research thread (Kagi, 2026-11-03) says the useful direction is **retrieval over
summarisation**: keep the full store, retrieve only what the current turn needs. Disk is cheap;
re-prefill is not, and a rewrite breaks the prompt cache.

## Goal

One small local index that answers "find the document/note/change about X" and returns a **stable
source reference**, not a copy of the content.

- **Store**: one SQLite file with the `sqlite-vec` extension. No server, no daemon. Delete and
  rebuild is allowed.
- **Model**: a small text-embedding model (about 30-90 MB, e.g. bge-small / e5-small / gte-small),
  served once on brys or run on CPU. The 4 B `qwen3-embedding-4b` is larger than this task needs.
  Fits under 1 GB VRAM; CPU is enough for query time.
- **Sources** are pluggable. This task covers **files and notes, and jj history**:
  - files/notes: chunk text by heading or about 1-2 k tokens;
  - jj history: one record per change, from `jj log -r 'all()'` with change id, description,
    changed paths and bounded diff hunks.
- **Incremental**: skip an unchanged item by content hash. A rebuild must not re-embed the corpus.
- **Query**: a thin CLI (`kdn-rag query "..."`), plus Pi tools `rag_search` (returns refs and
  scores) and `rag_fetch` (returns the stored text of one ref). The Pi tools mirror the session
  tools, so an agent learns both the same way.

## Shape

```sql
documents(id, kind, source_ref, chunk_no, text, hash, updated_at)   -- kind = file | note | change
vec_documents(embedding)                                            -- sqlite-vec virtual table
```

`source_ref` is the product: `file:docs/x.md#L40-90`, `note:<name>`, `change:<change-id>`. A hit
points at the original. The index never becomes the authority for the content.

## First step: a poor-man's RAG from OKF summaries

Measured on 2026-11-03: **308 documents** already carry OKF frontmatter with `type`,
`description` and `timestamp`. Only one has `tags:`; none has `resource:`. The corpus is therefore
already an index: the `description` is a one-sentence, model-authored summary, and a scan over 308
of them is milliseconds and deterministic.

So do not start with embeddings. Start with a lexical and fuzzy retrieval over the modern OKF
frontmatter, then fetch the exact document:

1. `frontmatter_index { roots, match?, type?, tags? }` returns `ref<TAB>type<TAB>tags<TAB>description`.
   `match` is a fuzzy match over `description` (Fuse.js is already vendored for the session tools).
2. `ref_resolve { ref }` returns the exact content of the chosen ref (the `doc_fetch` step below).
3. Add `tags:` to the top-level docs so a query can also filter by facet (`zfs`, `pi-harness`,
   `jj`). Tags are cheap and they make the index queryable, not only fuzzy.

This is the two-stage shape the session tools already use: a cheap index, then an exact fetch. It
needs no model, no network, and no store. Embeddings (`local-rag-index` proper) are the upgrade for
when lexical match fails; they do not replace this layer, because the text they embed is the same
OKF summary.

An agent can also keep the summaries fresh: the index reports any document whose `timestamp` is
older than its content, so an agent can rewrite one `description:` at a time. Do not add
`verified`/`stale_after` until a checker enforces them.

## Stable references

One reference grammar across every source, resolved by one tool. A reference is stable: it names a
stored identity, never a transient position.

| ref                        | resolves to                                            |
| -------------------------- | ------------------------------------------------------ |
| `docs/x.md`                | the file                                               |
| `docs/x.md#section`        | that heading's section                                 |
| `src/a.nix#L10-25`         | that line window                                       |
| `change:<change-id>`       | `jj show` for that change                              |
| `session:<session-id>#<n>` | one session step (`session_digest` / `session_detail`) |
| `ente:<asset-id>#t=90-120` | a media description (`rag-media-ingest`)               |

Rules:

- Use a repository-relative path; it stays valid in every checkout.
- Never cite a bare line number without an `#L` anchor; line numbers move, an anchor is checked.
- Prefer a stored identity (`change:`, `session:`) over a position.
- `ref_resolve` rejects a ref it cannot resolve instead of guessing.

The point of a stable reference is that one agent can cite it and a later agent can resolve it to
the same content.

## Cost (measured inputs from the fleet)

- Corpus for this repository: about 0.5 M tokens of digests; index about 1-2 MB.
- Build: minutes on CPU, seconds on a GPU; query: one embedding plus dot products, milliseconds.
- Rerank is optional and only over the top about 20 hits.

## Acceptance

- `kdn-rag index --files docs --notes . --jj` builds a store and prints counts per `kind`.
- A second run embeds **only** changed items (proof: a counter or the run log).
- `kdn-rag query "zfs arc cap"` returns the `docs/tasks/2026-11/zfs-arc-cap` file with a
  `file:` ref, and a `change:` ref for the commit that touched it.
- The store is git-ignored; no secret and no file body is written anywhere else.
- Before any embeddings: `frontmatter_index` answers "find the doc about X" over the 308 OKF
  descriptions, and `ref_resolve` opens the chosen ref exactly.
- One reference grammar resolves docs, code line windows, jj changes and session steps.
- Pi `rag_search`/`rag_fetch` work through the wrapper for a repository-scoped store.

## Out of scope

Images and video: see `rag-media-ingest`. A hosted vector database: the point is one file.

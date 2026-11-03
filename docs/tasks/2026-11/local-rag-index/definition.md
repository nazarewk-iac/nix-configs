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
- Pi `rag_search`/`rag_fetch` work through the wrapper for a repository-scoped store.

## Out of scope

Images and video: see `rag-media-ingest`. A hosted vector database: the point is one file.

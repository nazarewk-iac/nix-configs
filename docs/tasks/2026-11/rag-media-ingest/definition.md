---
type: Task
description: Index images and the images inside documents by describing them with a vision model, then embedding the derived text next to a stable source reference (Ente asset, PDF page). Video is a stated future extension.
status: open
authored_by: agent
timestamp: 2026-11-03T11:47:41+01:00
---

# Media ingestion for the retrieval index

## Context

`local-rag-index` builds the store, the embedding step and the query path. This task adds media as
another source of `documents` rows. The rule stays the same: **derive text, index text, keep a
stable pointer**. Do not vectorise pixels; that needs a joint model (CLIP/SigLIP/ColPali) and a
second index, and it is not needed for "find the photo that has X".

## Goal

```
image bytes -> vision model -> text (caption + OCR + tags + EXIF/filename/album)
                                    |
                                    v
        documents(kind=image, source_ref, text) -> embeddings
```

- **Describe once, cache by content hash.** A rebuild must not re-describe an unchanged image.
- **`source_ref` is the product.** Use a stable, actionable pointer: `ente:<assetId>`,
  `file:docs/paper.pdf#p=3#img=2`. The index never stores the image.
- **Model**: `vision-quick-fast` (qwen3-vl-8b, GPU) for bulk captions; escalate to
  `vision-std-fast` (30 B) only for hard OCR or diagrams. Qwen-VL does OCR itself, so no separate
  OCR tool is needed.
- **Documents with embedded images** (PDF/Markdown): extract each image, describe it, and index
  per image with a page/ordinal reference.

## Ente Photos

- Read metadata without downloading full originals: album, filename, EXIF, captions. Describe from
  a thumbnail.
- Privacy: the derived description is text in the local index. The image bytes go only to the
  self-hosted brys vision model. State this in the tool documentation.

## Video (future, not in this task)

The same schema holds video with `kind = video` and a time range in the ref:
`ente:<assetId>#t=90-120s`. Video adds derivers, not a new shape:

- keyframes by scene-change sampling (ffmpeg), each described by the vision model;
- audio to a timestamped transcript (ASR; or `audio-std-mid` qwen3-omni for audio understanding);
- chunk by time window (about 30 s), embed the combined caption and transcript.

New dependencies for video are ffmpeg and an ASR model. Nothing else changes.

## Acceptance

- `kdn-rag index --images <dir>` and an Ente source add `kind=image` rows with `source_ref`.
- A second run skips unchanged images (proof: describe-count log).
- `kdn-rag query "whiteboard with the network diagram"` returns the source ref, not the image.
- A PDF with a figure returns a `file:...#p=N#img=M` ref.
- No image bytes are stored in the repository or the index.

---
type: Rule
description: "AI-XF Level 2 in the memory bundle: a stable slug id, typed links mirrored by body links, the manifest, and the validator gate."
timestamp: 2026-11-16T15:45:00+01:00
---

# AI-XF in the memory bundle

Full doc: [docs/ai-xf.md](../../docs/ai-xf.md). AI-XF is a strict superset of OKF v0.2; the bundle
stays valid OKF.

- **Every concept has a stable `id`.** A simple slug, no `/`; the id survives a file move or
  rename. Do not derive it from the path at read time.
- **Every typed `links` entry is mirrored by a body link.** `rel: depends-on` in frontmatter and
  `[Target](target.md)` in the body must name the same concept.
- **`manifest.ai-xf.yaml` declares the version and name.** Do not change the version without the
  validator.
- **Level 2 is the gate.** `ai-xf-validate .agents/knowledge --level 2` must pass next to
  `okf-memory validate .agents/knowledge --strict --drift`.
- **No federation yet.** Level 3 (`namespace`, `ai-xf://` references, shared vocabularies) is not
  used; do not add a namespace or a qualified reference.
- **`okf-agent-memory` owns the files.** It preserves `id` and `links`; if a tool drops them, the
  validator catches it. Do not hand-edit `index.md`/`log.md`.
- **`kdn-okf` reads the mirrored links.** It ignores `id`/`links`; the body link is the graph edge
  it sees.

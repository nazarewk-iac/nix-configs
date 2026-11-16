---
type: Decision
title: One writer per bundle
description: okf-agent-memory writes .agents/knowledge; kdn-okf only reads it.
generated: { by: agent/cli, at: "2026-11-16T14:12:45Z" }
status: stable
---

`create`/`update` maintain `index.md` and `log.md`. `kdn-okf generate-index` is for documentation bundles and must not run on the memory bundle.

# Related Concepts
- [Cache outside the bundle](cache-outside-bundle.md): Both keep tool state out of the bundle.

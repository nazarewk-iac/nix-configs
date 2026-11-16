---
type: Decision
title: Cache outside the bundle
description: "kdn-okf caches in the XDG cache, never inside the bundle."
generated: { by: agent/cli, at: "2026-11-16T14:12:34Z" }
status: stable
---

The cache lives in `$XDG_CACHE_HOME/kdn-okf/<sha256(bundle-root)>/index-v1.json`; `--cache-dir` overrides it.

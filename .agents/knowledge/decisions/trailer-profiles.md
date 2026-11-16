---
type: Decision
title: Agent trailer profiles
description: "Agent commits carry Assisted-by, Generated-by, Session-Id, Harness and Model."
generated: { by: agent/cli, at: "2026-11-16T14:12:45Z" }
status: stable
id: trailer-profiles
links:
  - rel: relates-to
    to: one-writer-per-bundle

---

# Agent trailer profiles

`kdn-jj-meta` owns the trailer profiles. `--profile` replaces the set; `--coauthor` adds the agent only; the human is never a co-author and `Signed-off-by` stays human-only.

## Related Concepts
- [One writer per bundle](one-writer-per-bundle.md): Attribution and memory are separate tools with separate writers.

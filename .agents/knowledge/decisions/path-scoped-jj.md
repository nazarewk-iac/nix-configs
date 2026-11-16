---
type: Decision
title: Path-scoped jj commands
description: Every path-taking jj command lists the files the session owns.
generated: { by: agent/cli, at: "2026-11-16T14:12:45Z" }
status: stable
id: path-scoped-jj
links:
  - rel: relates-to
    to: trailer-profiles

---

# Path-scoped jj commands

Parallel sessions share `@`. A path-less `jj split`, `squash`, `absorb`, `commit`, `restore`, `status` or `diff` can sweep another session's work into a commit. Pass every file the session owns.

## Related Concepts
- [Agent trailer profiles](trailer-profiles.md): A scoped commit is also the commit that carries the trailers.

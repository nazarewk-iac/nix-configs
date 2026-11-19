---
type: Decision
title: Never push
description: The user reviews and pushes every change.
generated: { by: agent/cli, at: "2026-11-16T14:12:45Z" }
status: stable
id: no-push
links:
  - rel: relates-to
    to: path-scoped-jj
---

# Never push

Agents commit with jj and never run `git push`, `jj git push`, `jj sync-remotes` or `jj sync-upstream`. The user reviews from the tip and pushes.

## Related Concepts

- [Path-scoped jj commands](path-scoped-jj.md): Both govern how an agent commits with jj.

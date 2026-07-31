---
type: Rule
description: "Short pointer to the jj mandate: never push; leave an empty change on top only when you wrap up finished work."
timestamp: 2026-07-31T14:00:00+02:00
---

# Version Control

See [jujutsu-vcs.md](jujutsu-vcs.md) for the full jj mandate and the patterns this repo uses.

- Leave an empty `jj` change on top **only when you wrap up finished, described work**. The empty
  change gives the user a clean working copy to review from.
- Do NOT stack an empty change above undescribed or parked work — that buries the working copy.
  Keep the working copy `@` on the parked work itself.
- Never create an undescribed change in the middle of the graph as a checkpoint or a container.
- Never push changes — the user reviews and pushes.
- Use conventional commit format (`feat:`, `docs:`, `chore:`, `fix:`).

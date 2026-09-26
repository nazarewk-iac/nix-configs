---
type: Rule
description: Tells the agent to surface a macOS-only quirk to the user and record it in docs/darwin-quirks.md after the user confirms.
timestamp: 2026-10-01T14:58:34+02:00
---

# Darwin quirks

When a task on a macOS host meets a behaviour that a Linux habit does not predict, do this:

1. Stop and name the quirk to the user. State the symptom and the likely cause in one or two
   sentences.
2. Ask the user to confirm the quirk is real and worth recording.
3. After the user confirms, add one entry to [docs/darwin-quirks.md](../../docs/darwin-quirks.md).
   State the symptom, the cause, the evidence, and the fix.

Do not record a quirk without the user's confirmation. Do not guess a cause — test it first.

The full entries are in [docs/darwin-quirks.md](../../docs/darwin-quirks.md).

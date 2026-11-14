---
type: Task
description: Design and implement conflict resolution better than "latest modified wins" for the sops-encrypted file-tree rosec provider.
status: open
authored_by: agent
timestamp: 2026-11-14T18:00:00+01:00
---

# rosec sops provider — conflict resolution

Follow-up to the `secret-service-backend` task. The custom rosec provider stores one
`sops`-encrypted file per item in a Syncthing/Nextcloud-synced tree. Its first conflict rule is
**latest `modified` wins**: among the item's files (the canonical file and any Syncthing
`*.sync-conflict-*` copies), the provider serves the one with the newest `modified` timestamp.

That rule is a deliberate placeholder. It can lose a secret when two hosts edit the same item
concurrently, it depends on wall-clock agreement, and it hides the loser instead of surfacing it.

## Problem

1. Two hosts edit the same item while offline; Syncthing produces a conflict copy. Latest
   `modified` wins silently — the other value is still on disk but no client can see it.
2. Clock skew between hosts makes "latest" wrong.
3. A secret value is opaque: there is no semantic merge, but the _item_ has structure (label,
   attributes, several named secrets), so a per-field merge is possible in principle.
4. The sync transports differ: Syncthing renames conflict copies, Nextcloud keeps versions,
   git merges text. The rule must survive all three.

## Requirements

- No silent data loss: a losing version stays reachable (a conflict item, a conflict list, or a
  version history) until the user resolves it.
- Deterministic ordering independent of wall clocks: a per-item revision (monotonic counter + host
  id, or a Lamport/vector clock) or a content hash chain.
- Per-field merge where it is safe (label/attributes), "keep both" where it is not (secret
  values), and a documented resolution command.
- Works with the existing provider interface (`Provider` trait, `write` capability) and the
  daemon's item model; no D-Bus changes if possible.
- Tested with a simulated two-writer scenario and a Syncthing-style conflict copy.

## Candidates to evaluate

1. **Lamport clock + host id per item** — a `revision` counter incremented on every write and a
   `host` field; conflict when counters are equal/divergent; keep both on conflict.
2. **Per-item vector clock** — exact causality, more state per item.
3. **Per-secret-key LWW register + item-level conflict list** — merge labels/attributes
   automatically, keep both secret values, expose `rosec conflicts list/resolve`.
4. **Content-hash chain** — each write references the previous file hash; a mismatch is a
   conflict; no clocks at all.

## Acceptance

- A design note with the chosen scheme, the file format change, and the sync-transport behaviour.
- The provider implementation in the rosec fork, with tests: two writers, a Syncthing conflict
  copy, a clock-skew case, and a resolution command.
- The `secret-service-backend` task's provider docs updated to point at the new scheme.

## References

- Provider: the `rosec-sops` crate in the rosec fork (created by the parent task).
- Session journal: `.cache/agents/opencode-20261113-ses_e2933f0deffeERrdlOBc6LRMXs/poc/`
  (`results.md`, `summary.md`, `research.rosec.md` §15).
- Syncthing conflict naming: `<name>.sync-conflict-<date>-<time>-<host>.<ext>`.

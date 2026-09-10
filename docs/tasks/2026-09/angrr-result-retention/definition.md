---
type: Task
description: Stop angrr from deleting a live `result` out-link, and make the Darwin angrr job run at all.
status: open
authored_by: agent
timestamp: 2026-09-10T14:20:00+02:00
---

# Keep the newest `result` out-link, and start angrr on Darwin

angrr deletes a `result` symlink that a person still uses. The cause is measured, and two changes
fix it. [research.md](research.md) holds the evidence with source citations.

`brys` and `oams` both set `services.angrr.enable = false` because of this defect
(`hosts/brys/default.nix:452`, `hosts/oams/default.nix:321`). On the Darwin host angrr has never
run one single time, so the defect is latent there.

## The two changes

Land change A first. Change B switches on deletion that has never executed on Darwin.

### Change A — a `filter` program for the `result` policy

Add one `filter.program` key to the `result` temporary-root policy in
`modules/universal/profile/machine/baseline/default.nix`, inside the `result = { … }` block.

The program reads one JSON object per candidate on stdin, and the exit code is the verdict:

| Field | Value |
|---|---|
| stdin | `{"path":"<out-link>","gc_root":"<gcroots/auto entry>"}` |
| exit 0 | angrr monitors the path, so `period` can expire it |
| exit non-zero | angrr ignores the path, so angrr keeps it forever |

The key is `snake_case`, because angrr's `Input` struct carries no `rename_all`.

The program groups the `result*` siblings of one directory by name stem, where a trailing
`-<digits>` is a generation suffix. It keeps the newest member of each group, and it marks every
superseded member as prunable. So `result-fd` and `result-fd-1` are one group.

A prototype was built and measured — see [research.md](research.md) § "Change A, measured".

Accept one trade-off: a `result*` out-link that is the only member of its group becomes immortal.
Only a group with a superseded member ever prunes.

### Change B — a timer for the Darwin angrr job

Add `services.angrr.timer.enable = true;` in a `kdnConfig.util.ifTypes [ "darwin" ]` guard.

nix-darwin has no `nix-gc.service`, so the Darwin angrr module cannot hook one. Without a timer the
launchd job carries `RunAtLoad = false` and no `StartCalendarInterval`, so angrr never starts.

Keep `timer.dates` at its default. The Darwin type is `listOf (attrsOf int)`, unlike the NixOS
`str`, so it cannot go in the shared block.

## Exit test

1. `sudo angrr run --dry-run --log-level debug --interactive never` on each host. Read the
   `Keep`/`Remove?` lines per path and per policy before the first real pass.
2. Remove `services.angrr.enable = false;` from `hosts/brys/default.nix:452` and
   `hosts/oams/default.nix:321`, then build both hosts.
3. Confirm the newest out-link of every group survives a real pass.

## A disagreement to note, and to decide when this task runs

`nix.gc.options = "--delete-older-than 7d"` is set for every host, and angrr's
`profile-policies.system` keeps `keep-since = "14d"` with `keep-latest-n = 5`. The two disagree
about a generation between 7 and 14 days old.

Decide it then, not now.

## Follow-up, not in scope here

- `modules/den/aspects/angrr.nix` is arguably the real destination. `devenv-cli.nix:33-41` already
  carries the `keep-outputs`/`keep-derivations` half of this topic. Fix in place first.
- `remove-root = false` removes the out-link itself, not the `gcroots/auto` entry. The option name
  reads backwards against angrr's own `docs/config.md:34-37`. Decide whether
  `services.angrr.settings.remove-root = true` is the behaviour you want.
- An out-link whose name does not start with `result` (for example `v7-brys`) matches no policy, so
  angrr keeps it forever. The `result` policy covers less than the name suggests.

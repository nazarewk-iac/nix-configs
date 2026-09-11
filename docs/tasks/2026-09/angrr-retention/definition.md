---
type: Task
description: Start the angrr retention job, add a policy for the devenv root class, and land it in report-only mode.
status: in-progress
authored_by: agent
timestamp: 2026-09-11T00:00:00Z
---

# Start angrr, and give the `.devenv` root class a policy

angrr is enabled and it removes nothing useful. Three facts, all measured on 2026-09-11:

1. `services.angrr.timer.enable` is set nowhere in this repository. On Darwin that option is the
   only trigger, so `/Library/LaunchDaemons/org.nixos.angrr.plist` holds `RunAtLoad = false` and no
   `StartCalendarInterval`. The daemon has never run one single time.
2. 24 of the 29 auto garbage-collector roots of the Darwin host live under `.devenv/`, and 13 of
   them were last written between 43 and 105 days ago. No policy matches them. The `direnv` policy
   targets `/\.direnv/`, which is a different directory, and this repo uses no `.envrc`.
3. Zero `.direnv` roots and zero `result*` roots exist there today. Both existing temporary-root
   policies match nothing.

A disk incident on 2026-09-11 made the cost visible. Free space fell from 289 GB to 33 GB during a
three-host build. A collector run freed 0 MB, and nine stale `result*` symlinks needed a manual
removal.

## What this task does

| Change | Where | Effect |
|---|---|---|
| A | both trees | Add a `devenv` temporary-root policy, `path-regex = "/\\.devenv/"`, `period = "30d"`. |
| B | Darwin branch of both trees | Set `services.angrr.timer.enable = lib.mkDefault true;`. |
| C | Darwin branch of both trees | Write `StandardOutPath` and `StandardErrorPath` to `/var/log/angrr.log`, because launchd sends a daemon's output to `/dev/null` when neither is set. |
| D | both trees | Add one option, default `true`, that puts angrr in report-only mode. |

The full reasoning, every source citation and eight open questions are in the design that this task
carries. The `filter.program` route stays **out of scope** — see `## Not in scope`.

## Change D — the safe first state

Declare one option per tree:

- `kdn.profile.machine.baseline.garbageCollection.dryRun`, default `true`
- `kdn.profile-baseline-gc.dryRun`, default `true`

It adds `--dry-run` to `services.angrr.extraArgs` and it raises `services.angrr.logLevel` to
`debug`. angrr then prints one verdict line per candidate and it removes no file.

The default is `true` because the Darwin daemon has never executed. Its first pass would delete
against an unreviewed 29-root set. The default costs one timer wake-up and one log read.

One accepted regression: host `etra` deletes today with no override, and this default stops that
until a person reads the report. `nix.gc.options = "--delete-older-than 7d"` keeps running there.

## Why 30 days

The measured age distribution of the 24 `.devenv` roots has an empty band. No root is between 17
and 42 days old. So 30 days reaps all 13 dead project roots and it keeps every root of an active
project, with a 13-day margin below and a 12-day margin above.

Accept one trade-off. angrr reads the mtime of the symlink target, and devenv rewrites a link only
when the derivation changes. So this repository's own `.devenv/bash-bash` link is 69 days old while
the repository is in daily use, and the policy removes it. devenv recreates it on the next shell
entry, so the cost is one rebuild.

## Not in scope

- **No `filter.program`.** The Darwin host holds zero `result*` roots, so the keep-newest-sibling
  rule has nothing to act on. The design records the measured filter contract for a later version.
- **No `angrr touch`.** It installs only through `programs.direnv.direnvrcExtra`, and this repo has
  no `.envrc`.
- **The `result` deletion defect** stays with [../angrr-result-retention/definition.md](../angrr-result-retention/definition.md).

## Exit test

1. Build: `nix build --no-eval-cache -L '.#checks.aarch64-darwin.bundle-den'`, then
   `nix run '.#darwin-rebuild' -- build`. The `angrr validate` step inside
   `services.angrr.configFile` proves the generated TOML at build time.
2. `sudo angrr run --dry-run --log-level debug --no-prompt` on each host. Read every `Keep` and
   `Remove` line, per policy and per path.
3. Confirm the Darwin plist now holds `StartCalendarInterval`, and confirm `/var/log/angrr.log`
   fills after the first wake-up.
4. Set `dryRun = false`, one host at a time.
5. Leave `services.angrr.enable = false;` in `hosts/brys/default.nix` and `hosts/oams/default.nix`
   until the predecessor task closes the `result` defect.

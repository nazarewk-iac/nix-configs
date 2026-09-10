---
type: Research
description: Why angrr deletes a live `result` out-link, why the Darwin job never runs, and the measured fix.
task: definition.md
authored_by: agent
timestamp: 2026-09-10T14:20:00+02:00
---

# angrr — why it deletes a live `result`, and why Darwin never runs it

Measured on 2026-09-10 against angrr source at
`/nix/store/cmbhn8aqg7pmd67c0sf7qq71vjiycrj4-source`. Every line number below points into that
tree. The parent task is [definition.md](definition.md).

## Question 1 — is angrr broken, or only switched off?

**It is enabled, and it has never run once on the Darwin host.**

```
launchctl print system/org.nixos.angrr
  →  runs = 0, RunAtLoad = false, no StartCalendarInterval
```

The cause: `services.angrr.timer.enable` is set nowhere in this repository. The Darwin module emits
`StartCalendarInterval` only under `lib.mkIf cfg.timer.enable` (`darwin/module.nix:48-50`).

NixOS needs no timer. `nixos/angrr.nix:412-417` makes the unit `wantedBy` and `before`
`nix-gc.service`. nix-darwin ships no such unit, so nothing triggers the Darwin job.

Two more facts, both checked:

- The generated config TOML is correct. Four suspected defects in the repository block are not
  defects.
- `angrr touch` never installs. It hangs off `programs.direnv`, which is a Home Manager option
  only.

## Question 2 — why a live `result` disappears

Four steps make the chain. Each one is necessary.

1. angrr reads the target of the `gcroots/auto` entry (`run.rs:316`), then calls
   `fs::symlink_metadata` — an lstat, with no follow (`run.rs:319`) — and takes the age from that
   result (`run.rs:357-364`). So angrr reads **the mtime of the person's own `result` symlink**.
2. A temporary-root policy decides on age alone: `root.age > period`
   (`policy/temporary.rs:74-83`). No other test applies.
3. Nothing renews that mtime. `angrr touch` could, and it never installs (see Question 1).
4. `remove-root = false` removes `root.path`, which is **the out-link itself** (`run.rs:546-550`).
   The store path then loses its last root, and the next `nix-collect-garbage` takes it.

So a `result` that a person keeps for weeks ages out and vanishes, however often they use it.

**devenv generations were never the victim.** No policy matches `.devenv/*`, and `run.rs:156` keeps
an unmatched root forever.

## Question 3 — the design

### Route 1, a profile policy, cannot work

`run.rs:463` requires `<name>-<N>-link` siblings that are already registered as garbage-collector
roots. A `result` out-link is not a profile, so `keep-latest-n` is a no-op for it.

### Route 2, a `filter` program, works

`filter.program` is `lib.types.str` (`shared/options.nix:223-226`), so `lib.getExe` supplies a
string that carries its own store dependency.

The stdin schema is `{"path":"…","gc_root":"…"}`. The `Input` struct has no `rename_all`
(`filter.rs:18-22`), so the key is `gc_root` with an underscore. Exit 0 means angrr monitors the
path; a non-zero exit means angrr keeps it.

`--filter-timeout` defaults to 1000 ms (`command.rs:110`). `extraArgs` reaches the `run` call at
`nixos/angrr.nix:389-392` and `darwin/module.nix:37-40`.

### Change A, measured

A prototype was built with `pkgs.writeShellApplication`, so it also passed the `shellcheck` pass:

```
/nix/store/11xiccvykgqa72v6h2y9vjys5aygxg6a-angrr-keep-newest-result
```

Behaviour against all 12 real matching out-links on the Darwin host:

| verdict | out-links |
|---|---|
| keep (exit 1) | `result-solo-brys-1`, `result-solo-brys-1-dist`, `result6-etra`, `result`, `result-fd`, `result-fix`, `result-hm-vfkit`, `result-probe`, `result-qemu-example`, `result-vfkit-example` |
| monitor (exit 0) | `result-fd-1`, `result-fix-1` |

Exactly the intended shape. The newest member of every group survives, and only the superseded
`-1` generations stay prunable.

Runtime on the worst directory here, which holds 8 siblings: 57, 58, 59, 64 and 66 ms across five
runs. That sits well inside the 1000 ms default, so `--filter-timeout` needs no change.

## What needs no further change

| Root kind | Why it is already safe |
|---|---|
| devenv roots | No policy matches them, so `run.rs:156` keeps them forever. |
| System profiles | The `system` profile policy keeps the union of 5 newest, under 14 days, current and booted. |
| Home Manager generations | On the Darwin host, home-manager is a nix-darwin module, so its closure sits inside the system generation. `~/.local/state/home-manager/gcroots` holds the only separate root. |
| User profiles | The `user` profile policy carries `enable = false`, and the `ignore-prefixes-in-home` defaults cover the rest. |
| The `direnv` policy | It matches `/\.direnv/`, and this repository produces no such root. |

## One item left unverified

The NixOS `nix.gc.dates` default was not read from source during this investigation. It was read
later: `[ "03:15" ]` at `<nixpkgs>/nixos/modules/services/misc/nix-gc.nix:24`.

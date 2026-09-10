---
type: Task
description: Move every personal data file into one folder that hosts reference, so the module tree carries no personal data and still evaluates when the folder is absent.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 009 — the personal data folder

Hub: [../generalization-plan.md](../definition.md). Depends on
[006](../006-direction-decision/definition.md) and
[008](../008-sops-default-inventory/definition.md).

Goal: **one folder** holds every personal data file. Modules carry no personal data. Hosts wire the
personal files in. The tree evaluates when the folder is absent.

The decision behind this: personal data in one place is easier to manage and to separate out. This
supersedes the earlier scattered `kdn-*.nix`-next-to-the-module precedent.
`modules/slots/ssh-access/kdn-graph.nix` is the last example of it.

Use **Pattern V1** throughout. A data move must not change any host's derivation.

## Why this comes after 006 and 008

- **After 006**, because the target framework decides how a host references the folder.
- **After 008**, because the sops inventory is the list of things that must become options before
  the data can move. A file move with no parametrization of its key schema only relocates the
  coupling.

## The three tiers of personal content

Measured across `modules/universal/` (194 files, 19,689 LOC):

| Tier | Size | Meaning |
|---|---|---|
| Publishable as is | ~158 files, ~13,600 LOC (~69%) | All 30 of `development/`, all of `toolset/` and `virtualisation/`, 38 of 40 `programs/`, 15 of 17 `hw/`, 11 of 14 `services/`. Standouts: `networking/router/default.nix` at 1827 LOC is fully options-driven; `disks/default.nix` at 675 LOC is a pure option schema. |
| Generic shape, personal data in defaults | ~22 files, ~3,500 LOC (~18%) | The work of this checkpoint. |
| Irreducibly personal | ~14 files, 2,573 LOC (~13%) plus 5 data files | Moves wholesale into the folder. |

## Tier 2 — the files to parametrize

| File | Personal data |
|---|---|
| `modules/universal/profile/default-secrets/default.nix` | `sopsFile = "${kdnConfig.self}/default.unattended.sops.yaml"` at 3 sites, plus that file's key layout — see 008 |
| `modules/universal/locale/default.nix` | defaults `Europe/Warsaw` and `pl` |
| `modules/universal/_stylix.nix:42` | a wallpaper URL on the creator's own Nextcloud |
| `modules/universal/development/nix/default.nix:27` | defaults to the creator's checkout path |
| `modules/universal/services/printing/default.nix` | a named printer and an IP |
| `modules/universal/services/samba/default.nix` | a home-LAN CIDR `192.168.0.0/16` |
| `modules/universal/disks/config.nix:157-162` | a host-specific ZFS rename |

## Tier 3 — the files to move

| Path | Content |
|---|---|
| `modules/universal/profile/user/{kdn,sn,bn}` | real `initialHashedPassword` values, gpg public keys, `authorized_keys`, u2f keys |
| `modules/universal/profile/machine/{baseline,basic,workstation}` | WiFi SSIDs, a 55-line `ssh_known_hosts` fleet |
| `modules/universal/profile/remote-builders/` | host inventory and homelab FQDNs |
| `modules/universal/profile/default-secrets/` | the sops configuration |
| `modules/universal/hw/yubikey/yubikeys.nix` | 2 YubiKey serials and age recipients |
| `modules/universal/hw/edid/` | 3 named monitors |
| `modules/universal/desktop/sway/**/kanshi` | named display arrangements |
| `modules/meta/k8s/clusters/pic` | a cluster definition |
| `modules/slots/ssh-access/kdn-graph.nix` | 176 LOC — coordinated with [007](../007-depersonalize-slots/definition.md) item 5 |

## The two hard blockers

Solve both, or the folder cannot be optional.

1. **`modules/universal/profile/machine/baseline` unconditionally sets
   `kdn.profile.user.kdn.enable = true`** (line 59). Every host that uses the baseline profile
   gets the creator's user account. An adopter needs the baseline without the user.
2. **`modules/universal/profile/default-secrets` hardwires one sops file path and its key schema.**
   See 008 for the exact dependency list.

## The kill switch that makes this feasible

`kdn.security.secrets.sops.files.<name>` **discovers** secrets. It reads the sops YAML metadata
instead of an explicit list — 18 files, 50 references. Consumers guard on `.allowed` or
`kdnConfig.util.hasSops`. So an adopter sets the allow flag false and the tree still evaluates.

**008 verifies this claim and lists every unguarded consumer.** Those are the real work. Do not
assume the guard coverage is complete.

## The profile topology constraint

`profile/**` sets **105 distinct `kdn.*.enable` paths** against **169 distinct `options.kdn.*`
prefixes**. About two thirds of the tree is reachable only through a profile. The chain is
`baseline → basic → desktop → dev → workstation`, by direct assignment.

The dependency is deliberately one-directional — only 19 files read `kdn.profile.*`. Keep it that
way. A profile is the entry point an adopter replaces; it must not become something modules read
back from.

## The den port — what stays in place, and where it goes

The den port (order 2 onward of [004](../004-den-spike/definition.md)) meets this personal data
before this checkpoint runs. The creator's instruction on 2026-09-10: **keep the files where they
are for now, and log where each one is expected to go.** So a den aspect may keep a personal
default in place, but the destination must appear in the table below.

The rule the port follows: **an aspect is universal code, and the data belongs to the consumer.**
So an aspect declares an option and reads it; the entity supplies the value. `ca` is the first
aspect that shows the shape — it declares `kdn.ca.<name>` and holds no certificate path of its own.
The test entity generates throwaway certificates instead.

| Aspect / slot | Personal data it holds today | Expected destination |
|---|---|---|
| `ca` | none — the option carries the data | n/a. The creator's own certificates join the folder as data files. |
| `ssh-agent` | none | n/a |
| `gh`, `devenv-cli`, `rosetta-builder` | none | n/a |
| `jj` | `upstream.remote` default `"kdn"`; `alwaysBlockedMessagePatterns` default `[ "scratchpad" ]` | the folder supplies both as data; the option default becomes empty. Overlaps [007](../007-depersonalize-slots/definition.md) item 1. |
| `opencode` | the commercial provider `requesty`; `"~/dev/**" = "allow"` in 5 blocks | the folder supplies the provider and the path allowlist. Overlaps 007 item 2. |
| `llm` | homelab FQDNs and overlay IP addresses in the option examples | the folder holds the real values; the examples become neutral. Overlaps 007 item 3. |
| `ssh-access` | `modules/slots/ssh-access/kdn-graph.nix`, 176 LOC of hosts, LAN addresses, WAN ports and `*.kdn.im` zones | the folder, wholesale. Already listed in Tier 3 above. This is why `ssh-access` is last in the port order. |
| `mcp` / `basic-memory` | knowledge-base paths under the creator's own `~/.local/share/…` | the folder supplies the paths as data. |

Keep this table current as each order lands. It is the input list for the move, and it records what
the port deliberately did not fix.

## Exit criteria

- Pattern V1: all 16 hosts have unchanged drvPaths, or you justify each change.
- Pattern V2: the tree evaluates with the personal folder absent, for at least one NixOS host and
  one Darwin host.
- `rg` finds no personal IP, FQDN, serial, SSID, or password hash outside the folder.
- A host in the folder-absent state still reaches a usable baseline — verify what an adopter gets,
  not only that evaluation succeeds.

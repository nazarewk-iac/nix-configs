---
type: Research
status: done
description: Turns every open item of task 013 into a one-line decision brief, ranked by what each answer unblocks, with each state measured from the code.
timestamp: 2026-09-11T12:00:00+02:00
authored_by: agent
---

# 013 — the open decisions, one brief each

Task: [definition.md](definition.md). Index of every deferred mark:
[../deferred-decisions.research.md](../deferred-decisions.research.md).

Each brief holds one question the creator answers in one line. I measured every `Today:` line from
the code on 2026-09-11, not from the task text. Section 3 item 4 needs no brief — it reads
`DECIDED 2026-09-11`, candidate A, and the switch ships.

Nine briefs follow, in order of what each one blocks. Two rows need no brief: see
[Already resolved](#already-resolved).

## The briefs

### 1. A profile: one bundle, or a list of aspects

- **Question:** Does a machine profile stay one bundle, or become a list of aspects each host names?
- **Today:** `modules/universal/profile/machine/desktop/default.nix:37-50` holds 14
  `lib.mkDefault true` lines in one file. `modules/universal/toolset/essentials/default.nix:22-56`
  holds 20 packages behind one switch. The den registry holds 21 aspects
  (`modules/den/lib.nix:36-56`) and no profile.
- **Options:** A — keep the profile and the per-item `mkDefault` opt-out; 0 lines, it ships today.
  B — one aspect per concern; about 14 new files plus a list per host; L. C — the profile becomes an
  aspect that includes other aspects; about 5 files; M.
- **Recommendation:** Pick C. It keeps one name per profile and still lets a host drop one concern.
- **Cost if we guess wrong:** 014 migrates the whole machine layer onto the wrong shape, so a second
  migration follows.
- **Blocks:** [014](../014-machine-layer-migration/definition.md) as a whole task,
  [006](../006-direction-decision/definition.md)'s unwritten output, rows 6, 17, 25 and 64.

### 2. The baseline user

- **Question:** Does the baseline profile declare a user, or does every host name its own?
- **Today:** `modules/universal/profile/machine/baseline/default.nix:30-35` declares
  `primaryUser.enable`, default `true`. Line `:115-117` puts
  `kdn.profile.user.kdn.enable = lib.mkDefault true` behind it. So an adopter opts out with one
  plain `false`, and the creator's user module still sits in the tree.
- **Options:** A — the baseline declares no user, and each of 16 host directories names one; M.
  B — keep `primaryUser`, and the personal data folder supplies the value; about 2 files; S.
- **Recommendation:** Take B. `data/` already exists and holds 9 tracked data files.
- **Cost if we guess wrong:** A later flip edits every host file and every reference to that user.
- **Blocks:** [009](../009-personal-data-folder/definition.md) hard blocker 1, row 36, the host
  layer of 014.

### 3. The personal host graph file

- **Question:** Does the personal host graph stay a tracked file here, or become git-ignored beside a
  tracked example file?
- **Today:** the graph sits at `data/slots-ssh-access.nix`, 190 lines, tracked (`git ls-files
  data/`). Three host files import it through `builtins.filter builtins.pathExists`
  (`hosts/brys/default.nix:12`), so an absent file evaluates. The move of 007 item 5 landed.
- **Options:** A — keep it tracked; an adopter overwrites it; 0 lines. B — git-ignore it and track
  `data/slots-ssh-access.example.nix`; 1 `.gitignore` rule plus one file rename; XS.
- **DECIDED (delegated class):** the shared schema default at
  `packages/kdn-ssh-access/module.nix:104` becomes neutral, and this repository restores the value in
  its own data file. That default names one person's login, so it is an option value, not structure.
- **Recommendation:** Take B, and land the decided default with it.
- **Cost if we guess wrong:** every adopter clone carries LAN addresses and zones it cannot use.
- **Blocks:** row 44, 007 exit criteria, 009 tier 3, umbrella gap 6.

### 4. stylix

- **Question:** Does theming get `kdn.stylix.enable`, or become one theme aspect?
- **Today:** `modules/universal/_stylix.nix:37` sets `stylix.enable = true` at plain priority, in a
  file every nixos, darwin, home-manager and nix-on-droid evaluation imports (`:11-28`). No
  `kdn.stylix.*` option exists: a grep over `modules/` and `hosts/` finds only two
  `stylix.targets.kde` host lines. The wallpaper is already a consumer value in `data/stylix.nix`.
- **Options:** A — add `kdn.stylix.enable`, default `true` here, and guard the file; about 6 lines;
  M. B — move the file to an aspect, so a host that names no theme aspect never evaluates stylix; L,
  and it waits on brief 1.
- **Recommendation:** Take A now. B follows for free with the 014 migration.
- **Cost if we guess wrong:** an adopter inherits a full theme, two font packages and a cursor with
  no switch at all.
- **Blocks:** rows 18, 19 and 20; the theming part of 014.

### 5. ZFS on a host with no ZFS filesystem

- **Question:** Does the baseline profile keep `kdn.fs.zfs.enable` on a host that mounts no ZFS
  filesystem?
- **Today:** yes. `modules/universal/profile/machine/baseline/default.nix:348` sets
  `lib.mkDefault true` for every baseline host. The comment at
  `modules/universal/fs/zfs/default.nix:95-106` states the rpi4 host lists no ZFS filesystem, so a
  `switch` compiles the ZFS module against the vendor kernel. That build is unproven. The comment
  cites line `:295` for the assignment; the real line is `:348`.
- **Options:** A — keep it; 0 lines, and the build stays unproven. B — derive the default from
  `config.fileSystems`, so a host with no ZFS dataset drops it; about 4 lines; S plus one rpi4 build.
- **Recommendation:** Take B, then run one rpi4 build to prove it.
- **Cost if we guess wrong:** the rpi4 build fails, or it compiles a kernel module nothing mounts.
- **Blocks:** the rpi4 build proof. No task waits on it.

### 6. The nix policy: ratify or revert

- **Question:** Does the tree keep both `kdn.nixConfig` and the three narrow options, or only one of
  the two routes?
- **Today:** both exist. `modules/universal/_options.nix:31-33` declares `nixConfig` plain, with
  today's value as the default; `readOnly` is gone. Lines `:41`, `:56` and `:77` declare
  `kdn.nixpkgs.allowUnfree`, `kdn.nixpkgs.permittedInsecurePackages` and `kdn.nix.substituters`, and
  `modules/universal/nix.nix:39-40,48,52` reads all three. The comment at `_options.nix:28-29` tells
  a consumer to prefer the narrow options.
- **Options:** A — ratify both routes; 0 lines. B — split fully and drop `nixConfig`; L, because
  `default.nix` and `_hm-bootstrap.nix` both copy the whole set.
- **Recommendation:** Ratify A. The comment already ranks the two routes.
- **Cost if we guess wrong:** a consumer replaces the whole set and loses the narrow options with no
  warning.
- **Blocks:** the exit state of rows 30 to 33.

### 7. jj and the MCP gateway

- **Question:** Does `kdn.jj` keep the MCP coupling, or does a separate `jj-mcp` aspect hold it?
- **Today:** the slot route gives an opt-out. `modules/slots/jj/default.nix:133-135` writes the jj
  backend and `kdn.mcp.programs.git.enable`, each at `lib.mkDefault`. The aspect route gives none:
  `modules/den/aspects/jj.nix:80` puts `kdn.mcp` in the aspect's own `includes`, so `jj` pulls the
  whole gateway.
- **Options:** A — keep the coupling; 0 lines. B — split a `jj-mcp` aspect; one new file, one
  registry entry in `modules/den/lib.nix` and one consumer list edit; S.
- **Recommendation:** Take B. An `includes` entry has no opt-out, and a `mkDefault` does.
- **Cost if we guess wrong:** every adopter of jj also runs an MCP gateway.
- **Blocks:** row 53, the aspect graph of [004](../004-den-spike/definition.md).

### 8. Homebrew taps: flake inputs, or one option

- **Question:** Do the 8 `brew-tap--*` flake inputs stay, or does `kdn.homebrew.taps` replace them?
- **Today:** the scan is already opt-in. `kdn.homebrew.tapsFromFlakeInputs` defaults to `false`
  (`modules/universal/_options.nix:141-145`) and `modules/universal/default.nix:247` guards the scan.
  `hosts/anji/default.nix:42` sets it `true`. The aspect route answers B for itself:
  `modules/den/aspects/homebrew.nix:49` declares `kdn.homebrew.taps`, default empty, and reads no
  input. `flake.nix` still carries the 8 inputs, so an adopter lock inherits 8 nodes.
- **Options:** A — keep the inputs; an adopter pays lock text only; 0 lines. B — remove them and pass
  paths; about 8 lines of `flake.nix` plus one host edit; M.
- **Recommendation:** Take B. The aspect route already proves the option shape.
- **Cost if we guess wrong:** 8 unused lock nodes in every adopter lock, for ever.
- **Blocks:** row 3, and one item of [010](../010-flake-input-overhead/definition.md).

### 9. The `kdn-` prefix

- **Question:** Does the `kdn-` unit-name and variable prefix stay fixed?
- **Today:** it is fixed. `modules/` holds about 40 distinct `kdn-` names — 28 sites of
  `kdn-ssh-access` and 18 of `kdn-secrets` lead the count — plus 13 `KDN_` environment variables.
- **Options:** A — keep it; 0 lines. Umbrella gap 10 reaches the same verdict for the option
  namespace. B — parametrize the prefix; L, because every script literal moves too.
- **Recommendation:** Take A. A rename buys an adopter nothing.
- **Cost if we guess wrong:** near zero. A rename stays possible at any later date.
- **Blocks:** nothing.

## Already resolved

| Row | State |
|---|---|
| 15 — the signing key file name | **ALREADY RESOLVED** by commit `660a81f3`. Both routes now default to a neutral file name with no initials: `modules/slots/signing/default.nix:82` and `modules/den/aspects/signing.nix:206`. The aspect comment at `:49` records the old value. |
| 58 — `llm` option examples | **ALREADY RESOLVED**. Every example holds a reserved documentation name or address: `modules/slots/llm/default.nix:455,473-474,486` and `modules/slots/llm/client/default.nix:78`. No homelab name and no overlay address remains. |
| Section 3 item 4 — the agent rules | **DECIDED 2026-09-11**, candidate A. `installAgentRules` defaults to `false` on 5 slots and 5 aspects. |

## Measured corrections to the task text

| Task text | Measurement |
|---|---|
| Row 15 "the default still carries the initials" | Refuted. `modules/slots/signing/default.nix:82` holds a neutral name. |
| Row 58 "examples hold homelab FQDNs and two overlay addresses" | Refuted. Every example uses a reserved documentation name. |
| Row 44 "only the file moves" | The move landed. The file is at `data/slots-ssh-access.nix` and three hosts import it through a `pathExists` filter. |
| `modules/universal/fs/zfs/default.nix:97-99` cites baseline `:295` | The assignment sits at `modules/universal/profile/machine/baseline/default.nix:348`. |
| The den registry holds 20 aspects | It holds 21 (`modules/den/lib.nix:36-56`). |

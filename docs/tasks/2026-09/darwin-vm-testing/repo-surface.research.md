---
type: Research
description: Inventory of what an ephemeral macOS VM test harness must run for the generalization plan, and which check and rebuild surface already exists in this repo.
timestamp: 2026-09-09T00:00:00+02:00
authored_by: agent
---

# Darwin VM testing — the repo surface

## Summary

Four exit tests need a fresh macOS guest. All four are activation-level or first-boot-level.
The plan's evaluation tests (Pattern V1, V2, V3) all pass on the creator's own laptop.
The biggest bootstrap blocker: a Darwin host build forces every `brew-tap--*` flake input, and one
of them uses `git+ssh://`, so it needs an SSH key.
`checks/` cannot host a fresh-guest test today. It holds only sandboxed `runCommand` derivations.

## 1 exit tests that need a fresh macOS guest

### The table

| Checkpoint | Exit criterion | Fresh guest | Why |
|---|---|---|---|
| 001 | New `checks/jj-experiments` cases pass (`docs/tasks/generalization-001-slots-sharing-readiness.md:215`) | no | The doc measures the same cases in `/tmp` with an isolated `HOME` (`:56`). |
| 001 | `nix flake check` passes (`:216`) | no | Needs an `aarch64-darwin` machine, not a clean one. |
| 001 | The standalone check passes for all 20 slots (`:217`) | no | Pure evaluation. |
| 001 | Pattern V3 — a scratch flake under `/tmp` consumes the template and evaluates (`:218-219`) | no | Pure evaluation, outside the repo tree. |
| 001 | Pattern V2 — the same evaluation succeeds with no SSH agent (`:220`) | partly | `SSH_AUTH_SOCK=` plus a `/dev/null` identity file reproduces it (`docs/generalization-plan.md:177-180`). A guest makes the state real, not simulated. |
| 002 | Pattern V3 — a scratch nix-darwin flake evaluates `config.system.build.toplevel.drvPath` (`docs/tasks/generalization-002-rosetta-builder-adopter-dropin.md:104-106`) | no | Evaluation only. Needs a Darwin machine. |
| 002 | Pattern V2 — the same evaluation succeeds with no SSH agent (`:107`) | partly | Same as 001. |
| 002 | The evaluation pulls in no `modules/universal` or `modules/meta` option (`:108`) | no | Pure evaluation. |
| 002 | The bootstrap phase and the steady phase both evaluate (`:109`) | no | Pure evaluation. |
| 002 | **A real `x86_64-linux` derivation builds on the Darwin host through the Rosetta builder** (`:110`) | **yes** | The creator's Mac already holds a Lima guest image and a live builder. The phase order only proves itself where no builder exists. |
| 003 | **A reader who follows only the runbook, on a stock Mac, builds an `x86_64-linux` derivation** (`docs/tasks/generalization-003-nix-darwin-getting-started.md:126`) | **yes** | The criterion says "on a stock Mac". |
| 003 | Every caveats row has evidence in this repo, or carries the unverified mark (`:127`) | **yes** | 8 of the 9 rows in the "Do not present these as verified" list (`:107-122`) are first-install or clean-machine faults. See the list below. |
| 003 | The prerequisites hold (`:60-69`) | partly | A guest is the only place where `system.primaryUser`, `trusted-users`, and the Rosetta Linux runtime are absent at the start. |
| 003 | No fork-only path appears (`:128`) | no | A text check. |
| 004 | Criteria 1-4 of the den spike (`docs/tasks/generalization-004-den-spike.md:38-93`) | no | The hub states that every criterion that decides the direction evaluates without a boot (`docs/generalization-plan.md:101`). |
| 004 | Phase 2 — prove Home Manager activation in a NixOS guest on a Darwin host (`docs/generalization-plan.md:97-100`) | partly | Needs a Darwin **host**, not a clean one. The guest is a NixOS guest, not a macOS guest. |
| 005 | The conformance test exists and runs (`docs/tasks/generalization-005-conditional-imports-requirement.md:106-107`) | no | Pure evaluation. |
| 006 | The direction decision (`docs/tasks/generalization-006-direction-decision.md:86-94`) | no | A written score table. |
| 007 | Pattern V1 — every host's drvPath is unchanged (`docs/tasks/generalization-007-depersonalize-slots.md:103`) | no | Needs a Darwin machine for the Darwin hosts (`docs/generalization-plan.md:201-202`). |
| 007 | Pattern V3 — a scratch adopter flake gets no commercial provider (`:104`) | no | Pure evaluation. |
| 008 | The four inventory lists (`docs/tasks/generalization-008-sops-default-inventory.md:106-111`) | no | Read-only research. |
| 009 | Pattern V1 — all 16 hosts keep their drvPath (`docs/tasks/generalization-009-personal-data-folder.md:98`) | no | Needs a Darwin machine. |
| 009 | Pattern V2 — the tree evaluates with the personal folder absent, for one NixOS host and one Darwin host (`:99-100`) | partly | Evaluation only. A guest makes the absent state real. |
| 009 | **A host in the folder-absent state still reaches a usable baseline** (`:102-103`) | **yes** | The criterion says "not only that evaluation succeeds". A usable baseline is an activation result. |
| 010 | The lock-overhead research deliverable (`docs/tasks/generalization-010-flake-input-overhead.md:133`) | no | Read-only research. |

### The four hard rows, in one place

1. `docs/tasks/generalization-002-rosetta-builder-adopter-dropin.md:110` — a real `x86_64-linux`
   build through the Rosetta builder, from the bootstrap phase.
2. `docs/tasks/generalization-003-nix-darwin-getting-started.md:126` — the whole runbook on a
   stock Mac.
3. `docs/tasks/generalization-003-nix-darwin-getting-started.md:127` — the 8 unverified caveats.
4. `docs/tasks/generalization-009-personal-data-folder.md:102-103` — a usable baseline with the
   personal data folder absent.

### The 8 unverified caveats that need a clean macOS

The 003 task lists them and tells the author to verify each one or mark it (`:107-122`):

| Line | Claim | Why a guest is the only test bed |
|---|---|---|
| `:111` | `/etc/nix/nix.conf`, `/etc/bashrc`, `/etc/zshrc` "already exists" backup-file errors | nix-darwin only writes these backups on the first activation. |
| `:112` | The literal `cannot add path … untrusted` error text | It needs a user that is **not** in `trusted-users`. |
| `:113` | A Determinate Nix versus upstream Nix versus Lix installer conflict | It needs a machine with no `/nix` yet. |
| `:114` | A need to install Rosetta 2 | The creator's Mac already holds `RosettaLinux` (`docs/multi-arch-builder.md:25-27`). |
| `:115-117` | SIP, `/nix` volume creation, `/etc/synthetic.conf` | Volume creation happens once, at install. |
| `:118` | Xcode command line tools or `xcrun` problems | The creator's Mac already holds them. |
| `:119` | Home Manager `useGlobalPkgs` backup collisions | This repo set `backupFileExtension` on day one (`modules/universal/default.nix:69`), so a collision needs a machine with pre-existing dotfiles. |
| `:121-122` | sudo with TouchID survives a rebuild | It needs a real reboot and relogin cycle. |

The remaining row (`:120`) restates the `backupFileExtension` prevention, so it is not separate.

### The three shared patterns, and what each one needs

| Pattern | Definition | Machine need |
|---|---|---|
| V1 — the drvPath equality gate | `docs/generalization-plan.md:156-170`. Record `nix eval --raw '.#darwinConfigurations.<host>.config.system.build.toplevel.drvPath'` before and after a refactor, then diff. Measured cost: 93 s per warm Darwin host (`:168-169`). | An `aarch64-darwin` machine with a warm store. A clean guest makes this **slower**, not more honest. |
| V2 — the adopter-hostile eval | `docs/generalization-plan.md:172-182`. First `SSH_AUTH_SOCK= GIT_SSH_COMMAND='ssh -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityFile=/dev/null' nix eval …`; second with no personal data folder. | Reproducible with env vars. A guest is the honest version, not the only one. |
| V3 — the scratch adopter repo | `docs/generalization-plan.md:184-187`. A flake **outside** this repo, under `/tmp`, that declares one input and enables one thing. | Any machine of the right platform. |

Note the plan's own rule: Darwin hosts build on a Darwin machine or through `remote=`
(`docs/generalization-plan.md:201-202`).

## 2 existing check and harness surface

### `checks/` — one subdirectory only

`checks/` holds `default.nix` plus a single subdirectory, `jj-experiments/`. There is no Darwin
check, no VM check, and no activation check.

`checks/default.nix` declares four checks:

| Check | Source | Tests |
|---|---|---|
| `hello` | `checks/default.nix:30-33` | The `checks.<system>` plumbing itself. It builds and touches `$out`. |
| `kdn-slug-pytest` | `checks/default.nix:35` | `pkgs.kdn.kdn-slug.passthru.tests.pytest`. |
| `zellij-llm-pytest` | `checks/default.nix:36` | `pkgs.kdn.zellij-llm.passthru.tests.pytest`. |
| `jj-experiments-pytest` | `checks/default.nix:45-50` | The whole jj pytest suite. This is the CI gate (`:42-44`). |

### The `jj-experiments` harness shape

The suite holds 16 `test_*.py` files and 93 test functions. Each file pairs with a `<group>.md`
file that explains its use cases (`checks/jj-experiments/conftest.py:11-12`).

**Isolation.** `Harness.__post_init__` (`checks/jj-experiments/conftest.py:417-461`) builds a
fresh env dict per test:

- `HOME` → `<tmp>/home`; `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME` →
  four sibling temp dirs (`:431-435`).
- `JJ_CONFIG` → a temp TOML that holds only a harness user name and e-mail (`:422-428, :436`).
- `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_SYSTEM=/dev/null` (`:437-438`).
- `JJ_EDITOR`, `EDITOR`, `VISUAL`, `GIT_EDITOR` → `true`, so no editor opens (`:440-443`).
- It then deletes every `GIT_CONFIG_KEY_*`/`GIT_CONFIG_VALUE_*` var and the git identity vars
  (`:445-461`), because git applies those even with `GIT_CONFIG_GLOBAL=/dev/null`.

**Scratch repos.** `Harness.mkrepo` (`:463-477`) makes `<tmp>/repos/<name>`, runs
`jj git init --colocate`, then applies the layered config. `Harness.make_bare` (`:479-490`) makes
`<tmp>/remotes/<label><n>.git` with `git init --bare`. `Repo.workspace_add` (`:348-367`) puts a
workspace in a **sibling** dir, never inside the repo tree. `Harness.cleanup` (`:504-505`) removes
the whole temp root. The `harness` fixture (`:508-514`) drives that on teardown; `mkrepo`
(`:517-520`) exposes the factory.

**Determinism.** Every commit gets an explicit, increasing timestamp through
`--config debug.commit-timestamp` (`:37-39, :210-216`), because the fork revset aliases rest on
jj `latest()`.

**The real slot config.** `Harness.slot_config` (`:492-502`) reads `JJ_FORK_CONFIG_TOML`. Without
it, the fork tests **skip**. `checks/jj-experiments/render-fork-config.nix` renders that TOML from
the real `modules/slots` tree through `mkSlots` (`checks/default.nix:18-24`).

**The pytest entry point.** There is no `pytest.ini` and no `pyproject.toml`. The entry point is
`python3 -m pytest -v <extraArgs>` inside a `runCommand`, at
`checks/jj-experiments/mk-pytest.nix:31`. That file sets `HOME="$(mktemp -d)"` (`:27`), copies the
suite into the build dir (`:28-30`), and puts `python3+pytest`, `jujutsu`, and `git` on
`nativeBuildInputs` (`:19-23`).

**Three invocation routes.**

1. `nix flake check` / `nix build .#checks.<system>.jj-experiments-pytest` — the sandboxed gate.
   Wired at `checks/default.nix:45-50`.
2. `nix run '.#jj-experiments-run' -- -k placement -x` — the subset runner. Defined at
   `flake.nix:453-476`; it calls `nom build --file checks/jj-experiments/subset-runner.nix` with
   the pytest flags as a JSON array (`:471-472`). `subset-runner.nix:21` uses
   `builtins.getFlake ("path:" + repo)`, so it reads the working tree, not the git index.
3. `devenv shell` in `checks/jj-experiments/`, then bare `pytest -k <case>`. The subdir
   `devenv.nix` puts `python3+pytest`, `jujutsu`, and `git` on the path (`:20-24`) and exports
   `JJ_FORK_CONFIG_TOML` in `enterShell` (`:28-31`). That subdir needs its own `devenv.yaml`, which
   points `nix-configs` at `path:../..` so the shell sees uncommitted edits. **That file is
   git-ignored.** `.gitignore:5` ignores everything, and the allow-list entry `!/devenv.yaml`
   (`.gitignore:39`) covers the **root** file only. So the subdir file exists only in the creator's
   working copy. A fresh clone gets route 1 and route 2, and must write route 3's `devenv.yaml`
   by hand.

A prior research pass already confirmed that a subset runs cleanly in the Nix sandbox
(`docs/tasks/jj-experiments-subset-check.research.md:20-27`).

### `flake.nix` — the `checks` output per system

- `systems = import inputs.systems` (`flake.nix:161`). The locked `nix-systems/default` input
  resolves to four systems: `aarch64-darwin`, `aarch64-linux`, `x86_64-darwin`, `x86_64-linux`.
  Verified: the locked `narHash` in `flake.lock` matches
  `/nix/store/yj1wxm9hh8610iyzqnz75kvs6xl8j3my-source`, whose `default.nix` lists those four.
- `checks = pkgs.callPackages ./checks (self.kdnMetaModule.config.output.mkSubmodule { moduleType = "checks"; })`
  (`flake.nix:477-481`). So `checks/default.nix` runs under `moduleType = "checks"`, not `darwin`.
- **Yes, checks run on `aarch64-darwin`.** Verified:
  `nix eval --raw '.#checks.aarch64-darwin' --apply 'cs: builtins.concatStringsSep " " (builtins.attrNames cs)'`
  returns `hello jj-experiments-pytest kdn-slug-pytest zellij-llm-pytest`.
- All four are platform-neutral `runCommand`-class derivations. None of them evaluates a
  `darwinConfiguration`, and none of them activates anything.
- `devShells = { }` (`flake.nix:482`). This repo uses devenv, not `nix develop`.

### Scripts that build or test a host

**`packages/darwin-rebuild/darwin-rebuild.sh`** — the Darwin wrapper.

- `packages/darwin-rebuild/default.nix:7-18` wraps it as `pkgs.writeShellApplication` with
  `coreutils`, `darwin-rebuild`, `nettools`, `nix-output-monitor`, and `openssh` on the path, and
  sets `runtimeEnv.DEFAULT_SRC = "${kdnConfig.self}"` (`:16`).
- Argument shape: `<cmd> [<host>|remote=<spec>] [nom flags…] [-- darwin-rebuild flags…]`
  (`darwin-rebuild.sh:59-122`). The `--` separator toggles which array receives a flag (`:116-122`).
- **`remote=` support is real.** `darwin-rebuild.sh:67-72` parses `remote=<spec>`; `:81-106`
  accepts four spec shapes, `<host>=<user>@<addr>` down to a bare `<host>`. A bare host name with
  no dot goes through `discover_hostname` (`:18-33`), which probes TCP port 22 against four
  private DNS search domains (`:37-42`). Those four domain names are the creator's own; a
  throwaway VM resolves none of them.
- Local path: `nom build --no-link '<flake>#darwinConfigurations.<host>.system' …` and then
  `sudo darwin-rebuild <cmd> …` (`:142`). It adds `--always-allow-substitutes` for the
  linux-builder case (`:139-140`).
- Remote path: `nix copy --to ssh-ng://<remote>` then `ssh -t <remote> nix run '<flake>#darwin-rebuild' …`
  (`:127-128`). So the **remote** must already hold a working Nix.
- It resolves the flake through `nix eval --raw "$src#self.sourceInfo.outPath"` (`:124`).

**`nixos-rebuild.sh`** — the NixOS wrapper. Same `remote=` parser (`:60-109`) and the same four
private search domains (`:35-40`). It adds `--target-host` and, on an architecture mismatch or an
explicit `+b` flag, `--build-host` (`:111-117`). Its own `sudo` path only applies to
`switch`/`boot`/`test` (`:123-129`).

**`apps.jj-experiments-run`** (`flake.nix:453-476`) is the only other test wrapper. There is no
VM wrapper, and no script boots any guest.

## 3 darwin hosts

The public chain holds **one** host with `"moduleType": "darwin"`:

| Host | `meta.json` | Visibility |
|---|---|---|
| `anji` | `hosts/anji/meta.json` — `system: aarch64-darwin`, `hostName: anji` | public |

A second Darwin host exists on the private fork chain only. Its directory name looks like a
corporate asset tag, so this doc names neither the directory nor any line in it. That follows the
rule at `docs/generalization-plan.md:263-265`: state the finding, omit the path.

### `hosts/anji` — what could not exist in a throwaway VM

| Item | Citation | Blocks a VM |
|---|---|---|
| `kdn.profile.machine.baseline.enable = true` | `hosts/anji/default.nix:37` | Yes, indirectly. The baseline sets `kdn.profile.user.kdn.enable = true` (`modules/universal/profile/machine/baseline/default.nix:60`). That sets `system.primaryUser` to the creator's user name and `users.users.kdn.home = "/Users/<creator>"` (`modules/universal/profile/user/kdn/default.nix:439,441`). A throwaway VM holds no such macOS account. |
| The default sops file | `modules/universal/profile/default-secrets/default.nix:21,24` set `sopsFile = "${kdnConfig.self}/default.unattended.sops.yaml"`. The baseline turns the profile on at `modules/universal/profile/machine/baseline/default.nix:64`. | Evaluation: no. Activation: yes. See section 4. |
| A named external volume path | `hosts/anji/default.nix:59` — `nix.linux-builder.workingDirectory` under a host-specific volume | Gated. `workstationTest = true` (`:10`) turns the whole `!workstationTest` block off (`:52`). |
| A base64 SSH host public key literal | `hosts/anji/default.nix:69` | Same gate (`:63`). Not quoted here. |
| `nix.settings.trusted-users = [ "@admin" ]` | `hosts/anji/default.nix:54` | Same gate. The global default already covers `@admin` (`modules/universal/nix.nix:36`). |
| `system.stateVersion = 6`; `home.stateVersion = "26.05"` | `hosts/anji/default.nix:40-41` | No. A VM can use the same values. |
| `environment.systemPackages = [ utm ]` | `hosts/anji/default.nix:48` | No. It is a plain nixpkgs package. |
| No hardware serial, no named disk device, no homebrew tap of its own | — | The host file names none. All taps come from the flake inputs; see section 4. |

`hosts/anji/default.nix:13-18` is also the reference for how a Darwin host consumes slots:
`kdnConfig.self.mkSlots { inherit pkgs; kdn.darwin.rosetta-builder.enable = true; kdn.devenv.enable = true; }`,
then `imports = [ … slots.config.darwin ]` (`:21-24`) and
`home-manager.sharedModules = [ slots.config.home ]` (`:44`).

### The second Darwin host — findings without paths

Each item below is verified by direct read. The path stays omitted, per
`docs/generalization-plan.md:263-265`.

| Item | Note |
|---|---|
| It overrides `kdn.profile.user.kdn.username` and `users.users.kdn.uid` on two adjacent lines | **This is the exact override pattern a fresh guest needs.** It is the only working example in the repo, and a public deliverable cannot cite it. |
| `system.stateVersion = 6` and `home.stateVersion = "26.05"` | The same values as `anji`. |
| It writes `/etc/resolver/*` files with private DNS server addresses | Fork-only content. Not quoted. |
| It sets `homebrew.casks` | A cask list. It needs Homebrew and network. |
| It enables the same slots as `anji`, plus `kdn.ssh-access` and `kdn.home.ssh-agent` | `kdn.ssh-access.defaults.identityFile` names a private key path. |

The fork chain also adds four more `brew-tap--*` flake inputs that need private SSH access. This
doc names none of them. Section 4 covers the mechanism.

## 4 bootstrap requirements

### The path a fresh guest takes

1. It installs Nix. The runbook must recommend the Lix installer
   (`docs/tasks/generalization-003-nix-darwin-getting-started.md:24`).
2. It builds `.#darwinConfigurations.<host>.system`. That is what the wrapper builds
   (`packages/darwin-rebuild/darwin-rebuild.sh:142`). `flake.darwinConfigurations` comes from
   `flake.nix:328-345`, filtered from `flake.hostConfigurations` on `moduleType == "darwin"`
   (`:329`). Each host dir needs a `default.nix` plus `meta.json` or `meta.nix`
   (`flake.nix:263-274`).
3. It runs `sudo darwin-rebuild switch --flake <flake>#<host>`
   (`packages/darwin-rebuild/darwin-rebuild.sh:125,142`).
4. `flake.darwinModules.default = ./modules/universal` (`flake.nix:327`) is the module a host
   imports (`hosts/anji/default.nix:22`).

### Hard blockers

| # | Blocker | Citation | Detail |
|---|---|---|---|
| H1 | **A `git+ssh://` homebrew tap input** | `modules/universal/default.nix:217-232`; `flake.nix:14` | The Darwin branch derives `nix-homebrew.taps` from **every** flake input whose name starts with `brew-tap--`. One of the three such inputs uses `git+ssh://git@github.com/…`. A fresh guest with no SSH key cannot fetch it. **Verified:** `nix eval '.#darwinConfigurations.anji.config.nix-homebrew.taps'` returns every `brew-tap--*` input, so the Darwin closure really forces them. Checkpoint 001 item 6 already asks for a `github:` URL (`docs/tasks/generalization-001-slots-sharing-readiness.md:199-207`) and states the target repo is public. |
| H2 | **A macOS account for the creator's user** | `modules/universal/profile/user/kdn/default.nix:439-441`; `modules/universal/profile/machine/baseline/default.nix:60` | The baseline profile sets `system.primaryUser`, `nix-homebrew.user`, and `users.users.kdn.home = "/Users/<creator>"`. nix-darwin does not synthesize `home`/`uid` for a macOS-created user, so Home Manager evaluates `home = null` without the override (`docs/tasks/generalization-003-nix-darwin-getting-started.md:78`). Checkpoint 009 names this its first hard blocker (`docs/tasks/generalization-009-personal-data-folder.md:71-73`). |
| H3 | **A sops age key that the default file accepts** | `modules/universal/security/secrets/age/default.nix:143-146`; `:119-133` | On Darwin, `sops.age.keyFile = "/var/lib/sops-nix/key.txt"` and `sops.age.generateKey = false`. The generator script converts `/etc/ssh/ssh_host_ed25519_key` to an age key (`:126-131`). A fresh guest has a **different** host key, so its age recipient is not in `default.unattended.sops.yaml` and decryption fails at activation. Soft escape hatch: set `kdn.security.secrets.allow = false` (`modules/universal/security/secrets/default.nix:13-21`). |
| H4 | **A wallpaper fetch from the creator's own server** | `modules/universal/_stylix.nix:39-45` | `stylix.image` defaults to a `pkgs.fetchurl` of a fixed-output image from a personal host. The comment says stylix needs it to evaluate (`:39`). The stylix module loads on Darwin too (`modules/universal/_stylix.nix:11-23`). A guest with no route to that host cannot realise the derivation unless a substituter holds it. Checkpoint 009 lists it as tier-2 personal data (`docs/tasks/generalization-009-personal-data-folder.md:47`). |

### Soft blockers

| # | Item | Citation | Why soft |
|---|---|---|---|
| S1 | `nix.settings.trusted-users` | `modules/universal/nix.nix:36` — `[ "@wheel" "@admin" ]` | macOS uses `@admin`. A guest admin account satisfies it. `allowed-users` adds `@users` and `@staff` (`:35`). |
| S2 | `nix.extraOptions` `!include` lines | `modules/universal/nix.nix:12-17` — `!include /etc/nix/nix.sensitive.conf` and `!include /etc/nix/nix.access-tokens.auto.conf` | `!include` tolerates an absent file. **Verified** on Lix 2.95.2 with `NIX_USER_CONF_FILES`: the `!include` form exits 0 on a missing file; the plain `include` form errors with `file '…' … not found`. |
| S3 | The sops metadata read at evaluation time | `modules/universal/security/secrets/sops/default.nix:80-90`; `lib/sops/default.nix:3-25` | `parseSopsYAMLMetadata` is a pure text parse of the plaintext YAML keys. It needs no decryption key. So evaluation succeeds with no key; only activation needs one. |
| S4 | `system.stateVersion` | `hosts/anji/default.nix:40` — `6`. The fork-only Darwin host uses `6` too. | A guest can set the same value. The runbook already states 6 (`docs/tasks/generalization-003-nix-darwin-getting-started.md:69`). |
| S5 | Homebrew itself | `modules/universal/default.nix:199,214-215` — `homebrew.enable = true`, `nix-homebrew.enable = true`, `nix-homebrew.enableRosetta` on aarch64 | nix-homebrew installs and owns the prefix. It needs network, not a pre-existing brew. `homebrew.taps` filters on the `homebrew/` prefix and marks the rest `trusted = true` (`:202-212`). |
| S6 | Lix on Darwin | `modules/universal/default.nix:95-106` | The repo overrides `doCheck = false` and `doInstallCheck = false`, because the Lix test suite fails on Darwin. |
| S7 | A credentialed substituter | `modules/universal/nix.nix:25-34` | The three substituters are public Cachix caches. None needs a token. The token file arrives through S2's optional `!include`. |
| S8 | A YubiKey or a 1Password socket | grep across `modules/universal` and `modules/slots` | The public tree names neither for a Darwin **host** build. 1Password appears only in a fork-only module subtree. The `ssh-agent` slot is opt-in and skips root, because root has no GUI login session and the launchd `gui/0` bootstrap fails with error 125 (`modules/slots/ssh-agent/default.nix:39-40`). |
| S9 | Linux-only packages in a shared list | `modules/universal/env/default.nix:31-51` | The repo filters `meta.broken`, `meta.unsupported`, `!meta.available`, and packages whose `outPath` fails `tryEval`, each with a warning. So a Darwin evaluation does not abort on them. |

### The one thing a guest gets for free

`rosetta-builder` is clean. `modules/slots/rosetta-builder/default.nix` is 41 lines. It uses no
`pkgs.kdn.*`, no `kdnConfig`, and its only external need is `inputs.nix-rosetta-builder`
(`docs/tasks/generalization-002-rosetta-builder-adopter-dropin.md:39-45`). It emits three values
into the `darwin` target: `nix-rosetta-builder.enable`, `nix-rosetta-builder.onDemand`, and
`nix.settings.builders-use-substitutes` (`modules/slots/rosetta-builder/default.nix:26-39`). So a
guest that calls `mkSlots` directly and never touches `modules/universal` avoids H1 to H4.

## 5 prior art in this repo

No document mentions **Tart** or **Mirage**. A case-insensitive whole-word grep across `docs/`
and `modules/` returns zero hits for both.

| Source | Conclusion already reached |
|---|---|
| `docs/multi-arch-builder.md` | The handover doc for a dual-arch Linux builder on Apple Silicon. It scores five options. Option A: binfmt plus QEMU-TCG inside the stock VM, zero new inputs but about 2.5× slower on compile-bound work, and QEMU on macOS cannot use Rosetta (`:99-116`). Option B: `applicative-systems/vzvm`, a `nix.linux-builder.package` swap, smallest diff, but an un-upstreamed overlay and a raw image, not qcow2 (`:124-153`). **Option C, chosen: `cpick/nix-rosetta-builder`** — Lima plus vz with `rosetta.enabled = true`, one VM that registers both systems, on-demand power-off, hardened defaults (`:155-181`). Option D: OrbStack or colima containers, only worth it when containers already exist in the toolchain (`:182-193`). Option E: two `nix.linux-builder` instances — **not recommended**, both cached images default to `hostPort = 31022` and you cannot build a custom-port image before a builder exists; "a fragile, multi-step dance (often needs `--option sandbox false`)", nix-darwin#1192 (`:195-200`). |
| `docs/multi-arch-container-builder.md` | Build a multi-arch OCI image index fully inside Nix, with no daemon and no registry round-trip. It **requires** the dual-arch builder from the doc above (`:7-13`). |
| `docs/tasks/multi-arch-rosetta-builder.done.md` | Option C landed as the `rosetta-builder` slot, the repo's first `darwin`-target slot. The bootstrap dance is **confirmed**: the first `darwin-rebuild build` reached the top with 151 builds in about 21 minutes, and the Lima guest image built on the stock `linux-builder` (`:40-42`). After activation, `/etc/nix/machines` lists both builders, and a real x86_64 ELF came out of the Rosetta VM (`:49-58`). One trap: a dangling `refs/remotes/<remote>/HEAD` symref gives `error: unexpected end-of-file` from a `git+file://` fetch (`:62-65`). |
| `docs/tasks/rosetta-builder-i686-linux.md` | A known limitation. Rosetta for Linux is x86_64-only, so the builder cannot build `i686-linux`. Checkpoints 002 and 003 must tell an adopter (`docs/generalization-plan.md:216-217`). |
| `modules/universal/profile/hardware/darwin-utm-guest/default.nix` | **The `darwin-utm-guest` feature flag exists, and it points the other way.** `kdnConfig.features.darwin-utm-guest` (declared at `modules/meta/default.nix:216`) gates a **NixOS guest that runs under UTM on a Darwin host**, not a macOS guest. When the flag is set and `moduleType == "nixos"`, it imports `"${inputs.nixpkgs}/nixos/modules/profiles/qemu-guest.nix"` (`:17-19`) and adds `xhci_pci` and `sr_mod` to `boot.initrd.availableKernelModules` (`:30-35`). The option defaults to the flag value (`:22-25`). **No host sets it today** — only `briv` and `kdn-rpi4-bootstrap` (`rpi4`) and `oams` (`microvm-host`) declare any feature. Checkpoint 005 lists it as one of the five conditional-import call sites (`docs/tasks/generalization-005-conditional-imports-requirement.md:66`). |
| `docs/generalization-plan.md:97-101` | microvm.nix supports a Darwin host at the pinned revision — `hypervisorsOnDarwin = [ "qemu" "vfkit" ]`, and `vmHostPackages` selects plain `qemu` off Linux. So checkpoint 004 could boot a NixOS guest on the Mac to prove Home Manager **activation**. The plan makes that phase 2, behind the evaluation criteria. **Unverified in this pass** — I did not find `hypervisorsOnDarwin` in the store copy of the microvm source. |
| `hosts/anji/default.nix:48` | The host already installs `utm`. So UTM exists on the Darwin machine today. |
| `docs/testing.md` | The repo's test convention: turn a one-off command into a committed pytest suite with a `nix-shell` shebang that builds the tool onto `PATH` and exercises the built artifact as a black box (`:8-12,:29-44`). Attach the suite as `passthru.tests.pytest`, then reference it from `checks/default.nix` (`:58-66`). |
| `docs/tasks/jj-experiments-subset-check.research.md` | A pytest subset runs cleanly in the Nix sandbox, and the fork tests skip without `JJ_FORK_CONFIG_TOML` (`:20-27`). |

## Blockers

These block a fresh-guest harness, in order of size.

1. **H1 — the `git+ssh://` homebrew tap input.** Any Darwin **host** build forces every
   `brew-tap--*` input (`modules/universal/default.nix:217-232`). One public input uses
   `git+ssh://` (`flake.nix:14`), and the fork chain adds four more. A guest with no
   key stops here. Checkpoint 001 item 6 already fixes the public one
   (`docs/tasks/generalization-001-slots-sharing-readiness.md:199-207`). The fork inputs stay a
   fork problem, so a guest can only test the public branch.
2. **H2 — the creator's macOS account.** Without an override, a Darwin host build wants
   `/Users/<creator>` and a matching `system.primaryUser`
   (`modules/universal/profile/user/kdn/default.nix:439-441`). The fork-only Darwin host holds the
   only working override example, and a public deliverable cannot cite it. A public example needs
   writing.
3. **`checks/` cannot host a fresh-guest test today.** All four checks are `runCommand`
   derivations in the Nix sandbox (`checks/default.nix:30-50`). A macOS guest needs a Hypervisor
   entitlement, a network, and a writable disk image. A Nix sandbox grants none of the three. So a
   VM harness belongs behind a flake **app** (the `apps.jj-experiments-run` shape at
   `flake.nix:453-476`), not behind `nix flake check`.
4. **No repo script boots any guest.** `packages/darwin-rebuild/darwin-rebuild.sh` and
   `nixos-rebuild.sh` both target a machine that already runs, over SSH
   (`darwin-rebuild.sh:127-128`, `nixos-rebuild.sh:111-117`). Their `remote=` host discovery probes
   four private DNS search domains (`darwin-rebuild.sh:37-42`), which a throwaway guest does not
   resolve. A harness must pass a full address or an IP, never a bare host name.
5. **Pattern V1 fights a fresh guest.** The drvPath gate costs 93 s per warm Darwin host and about
   25 minutes for 16 hosts (`docs/generalization-plan.md:168-170`). A cold guest has no warm store,
   so V1 belongs on the creator's machine and the guest only carries the activation tests.
6. **H3 and H4 need an escape hatch before a guest can activate anything.** H3 needs
   `kdn.security.secrets.allow = false`; H4 needs a `stylix.image` override. Neither escape hatch
   is documented for an adopter today.

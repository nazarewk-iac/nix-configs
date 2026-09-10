---
type: Task
description: Build a repeatable test loop that activates a nix-darwin configuration in an ephemeral macOS guest, so the generalization exit tests run on a clean machine.
status: open
authored_by: agent
timestamp: 2026-09-09T13:00:00+02:00
---

# Test nix-darwin in an ephemeral macOS guest

Four exit tests of [generalization-plan.md](../generalization/definition.md) need a **clean** Mac. Today
they run on the creator's own workstation, where a warm Nix store and a personal account hide the
faults an adopter meets first. This task builds the guest loop that makes those tests real.

## Research this task owns

- [tart.research.md](tart.research.md) — tool landscape, Tart license terms, GPU exposure,
  Nix-in-guest feasibility, timing budget.
- [repo-surface.research.md](repo-surface.research.md) — what the harness must run, and which
  check and rebuild surface already exists here.
- [lume.research.md](lume.research.md) — a real lume 0.5.3 unattended run on macOS 26.6.2, the
  shell result, three reproduced upstream defects, and the boot-to-SSH number.

Both files hold the measured evidence and the citations. This file holds only the decisions, the
blockers and the work.

## Target shape

Bake a golden image once. Then clone, activate and destroy per checkpoint. The one-time cost is a
27.31 GB image pull plus about 40 minutes for the Nix install and the first activation. The warm
loop then costs an estimated 2 to 5 minutes per checkpoint.

Do **not** run the cold path per checkpoint.

## The loop has two tiers, and the split is structural

Blocker 13 below is permanent, so no single guest covers the whole first-time setup. Split the
work and record which tier proved which claim.

| Tier | Runs where | Proves |
|---|---|---|
| A | macOS guest | Setup Assistant to stock macOS; the Nix install; `trusted-users` and the flakes settings; the repository clone; `devenv shell` and the slots; `darwin-rebuild build`; `darwin-rebuild switch`. |
| B | bare metal | The `nix-rosetta-builder` guest itself, and every real `x86_64-linux` build through it. |

## Measured on this host

| Claim | State | Evidence |
|---|---|---|
| `lume` installs with no `sudo` and no LaunchAgent | verified | 0.5.3 at `~/.local/bin/lume`, a 95-byte wrapper for `~/.local/share/lume/lume.app`. State in `~/.lume`. |
| `lume` builds a macOS guest from an IPSW without an operator | verified 2026-09-10 | It installs macOS and it answers Setup Assistant. But see the next two rows: `lume create --unattended` then **deletes** the guest. The 2026-09-09 "9 minutes" reading was that same failure, seen at the last line before the delete. |
| `lume create --unattended` keeps the guest | **disproved** 2026-09-10 | The command ran 14 min 04 s, installed macOS, applied the offline patch, failed **its own** SSH health check (60 attempts over 5 minutes), and deleted the guest. lume keeps no IPSW copy, so a retry re-pays the 19 GB download. |
| `lume create` plus `lume setup` keeps the guest | verified 2026-09-10 | `lume setup` is a separate subcommand with **no cleanup path**. `lume create` alone took 2 min 40 s. `lume setup` failed the same health check, and the guest survived. This is the split the harness must use. |
| The guest gives a usable shell | **verified** 2026-09-10 | `id -un` → `lume`, `sw_vers` → 26.6.2 / 25G83, `csrutil status` → enabled. Confirmed twice: through `lume ssh`, and through `/usr/bin/ssh` with the password `lume`. |
| lume's SSH health check is the defect, not the guest | verified 2026-09-10 | lume's own log prints `Wrote VNC config to VM via SSH` **4 s into** the same window in which it counted 60 SSH failures. |
| #1440 reproduces | verified 2026-09-10 | A VNC screenshot shows the guest parked on the Setup Assistant pane "Update Mac Automatically". It survives a cold boot. But it is the **post-login** assistant: `/var/db/.AppleSetupDone` exists and `who` shows `lume console`. SSH is unaffected, so the park blocks no test. |
| `cua` gives an agent full control of a guest | verified by source | `computer-server` is a guest-side agent on port 8000. It serves screen, pointer, keyboard, shell, file, PTY and browser surfaces over `/ws`, `/cmd`, `/status` and `/mcp`. It ships **only** in the `-cua` images (`cua_sandbox/runtime/images.py`), under launchd. Nothing bootstraps it into a vanilla guest. |
| Tart drives the pointer and the keyboard of a macOS guest | verified by source | `Sources/tart/Commands/Run.swift`: `--no-pointer` and `--no-keyboard` detach those virtual devices, so they attach by default. `--vnc-experimental` uses Virtualization.framework's own VNC server and works "in recovery mode and in macOS installation", unlike `--vnc`, which needs the guest OS up. |
| Rosetta 2 installs and works inside the guest | **verified** 2026-09-10 | `Install of Rosetta 2 finished successfully`, and `arch -x86_64` exits 0. So `x86_64-darwin` is testable in a guest. |
| A macOS guest runs a Linux virtual machine | disproved, permanent | Blocker 13, now confirmed from **inside** the guest: `kern.hv_support: 0` with `kern.hv_vmm_present: 1`. |
| A Nix-built `ssh` reaches the guest | **disproved** 2026-09-10 | Blocker 14. `/usr/bin/ssh` works. The Home Manager `ssh` and a Nix `bash` `/dev/tcp` both get `No route to host`, while `/usr/bin/nc` connects and prints the banner. |

Rollback: `lume delete rehearse` reclaims the guest disk, and `rm -rf ~/Library/Caches/lume-ipsw`
reclaims the IPSW cache. Together they hold 25 GB plus 19 GB today. The guest `rehearse` is left
**running** at 192.168.64.7. The full uninstall route stays in
[lume.research.md](lume.research.md).

## Decisions to make first

| Decision | Options | Why it blocks the rest |
|---|---|---|
| VM tool | Tart ≥ 2.33.0, lume, Lima, Mirage | Each has a different install path and a different image source. See the candidate table below. |
| Nix installer | Determinate, upstream, Lix | nix-darwin **aborts** when it detects Determinate. |
| Guest scope | public chain only | The fork chain adds four `git+ssh://` inputs a keyless guest cannot fetch. |

Tart relicensed to `FSL-1.1-ALv2` at 2.33.0, and the paid regime is retired. Install it with
`brew install openai/tools/tart`. The nixpkgs package is stale at 2.30.6 and still carries
`license.shortName = "fairsource09"` with `unfree = true`.

With Determinate, set `nix.enable = false;` and `determinateNix.enable = true;`, and import
`inputs.determinate.darwinModules.default`. Without that, activation stops with
`error: Determinate detected, aborting activation`.

## Candidate tools

Two tools cover two different jobs. Pick both, not one.

| Tool | License | Image source | First-boot test | Warm clone loop | Main risk |
|---|---|---|---|---|---|
| **Tart** ≥ 2.33.0 | FSL-1.1-ALv2 | OCI registry, `ghcr.io/cirruslabs/macos-*-base` | **no** — the published image is already past Setup Assistant, with a user and SSH ready | **yes** — `tart clone` is the fast path this task designs around | a third-party image you must trust; a 27.31 GB pull |
| **lume** 0.5.3 | MIT | Apple IPSW, plus its own registry | **yes** — `--unattended tahoe` drives Setup Assistant itself | yes, `lume clone` | v0.5.x; three open defects (#1440, #1513, #1514) |
| Lima | Apache-2.0 | `template:macos` | yes | weak — no OCI registry | least measured of the three here |
| Mirage | — | none published | unknown | unknown | v0.1, absent from nixpkgs, no image registry |

So the division of labour is:

- **lume proves the first-boot path.** It installs macOS from Apple's own IPSW and answers Setup
  Assistant. That is the only way to test "a stock Mac, hour zero". Tart cannot test it, because a
  registry image starts past that point.
- **Tart proves the repeatable path.** Bake once, `tart clone` per checkpoint. That is the warm loop
  the "Target shape" section costs out.

### `cua` is not a VM tool

`cua` is an agent-control layer. Its `computer-server` runs **inside** the guest on port 8000 and
serves screen, pointer, keyboard, shell, file, PTY and browser surfaces. Its host-side Python
client wraps those. It uses lume as its macOS backend, so it adds control, not virtualization.

You do not need it for nix-darwin. Every step of an activation is a command line, so plain SSH
covers all of it. `cua` earns a place in exactly two cases:

1. lume's unattended preset fails on a macOS release, and an agent must click through Setup
   Assistant itself.
2. A test must confirm something only the GUI shows.

One cost to state plainly: `computer-server` ships only in the `-cua` images
(`cua_sandbox/runtime/images.py`), under launchd. Nothing bootstraps it into a vanilla guest. So
you must install it into the guest yourself, and that installation **contaminates the clean-machine
premise**. Install it after the setup test, never before, and record it as a guest modification.

## What a macOS guest can and cannot test

This answers the wider question: the guest loop is not only for `rosetta-builder`.

| Feature class | In a guest | Note |
|---|---|---|
| Nix install, flakes settings, `trusted-users` | yes | The first thing an adopter gets wrong. |
| `darwin-rebuild build` | yes | Pure evaluation plus build. No activation. |
| `darwin-rebuild switch`, launchd daemons and agents | yes | Needs `sudo` inside the guest, which a throwaway guest permits. |
| The `/etc/{bashrc,zshrc,zshenv,zprofile}` takeover | yes | The most common first-time failure. A guest is the only honest test, because the creator's host already holds the `*.before-nix-darwin` files. |
| `system.defaults` (dock, finder, keyboard) | yes | Read the result back with `defaults read`. No GUI needed. |
| Home Manager activation, dotfiles, shell start-up | yes | |
| Homebrew and the `nix-homebrew` taps | yes | Needs network. A cask that wants a GUI also needs a display. |
| `devenv shell` and every slot | yes | Cheapest path: call `mkSlots` and never touch `modules/universal`. |
| sops secrets | partial | A new guest holds a new `/etc/ssh/ssh_host_ed25519_key`, so its age recipient is absent. Set `kdn.security.secrets.allow = false`, or re-key for the guest. |
| Stylix, wallpaper, any GUI theme | partial | Needs a display. Run with VNC, not `--display none`. |
| Rosetta 2 for `x86_64-darwin` | **yes — verified 2026-09-10** | Rosetta 2 translates; it does not virtualize, so blocker 13 does not apply. `softwareupdate --install-rosetta --agree-to-license` succeeded in the guest, and `arch -x86_64` exits 0. |
| TouchID `sudo` (`security.pam.services.sudo_local.touchIdAuth`) | no | A guest has no Secure Enclave and no TouchID sensor. |
| YubiKey, smartcard, any USB HID device | no | Virtualization.framework passes no arbitrary USB device through to a macOS guest. |
| FileVault, secure boot, full-disk encryption | no | |
| `nix-rosetta-builder`, or any Linux guest | no | Blocker 13. Permanent. Tier B only. |

## Start-up cost and programmatic control

Only one number below is measured. Check the state column before you plan around a row.

| Phase | Cost | State |
|---|---|---|
| lume, first ever: `create --unattended` with the IPSW download | **14 min 04 s**, about 19 GB down — then it **deletes** the guest | verified 2026-09-10. The 2026-09-09 "9 minutes" reading was the same failure, read at the last line before the delete. |
| lume, split path: `lume create` with a local IPSW | **2 min 40 s**, 25 GB on disk | verified 2026-09-10 |
| lume, split path: `lume setup --unattended tahoe` | it fails its own health check, and the guest survives | verified 2026-09-10 |
| Tart, first ever: base image pull | 27.31 GB | from the Tart research. The wall clock depends on the link. |
| Nix install plus first activation in the guest | about 40 minutes | estimate from the Tart research, not measured |
| lume: cold boot to an answered SSH command | **10 s and 11 s** | verified 2026-09-10, two runs, each from a confirmed `stopped` state with the mux socket removed. Far inside lume's own 5-minute budget. |
| Warm loop per checkpoint | 2 to 5 minutes | estimate in "Target shape", not measured |
| `clone` of a baked guest | seconds expected | unverified. APFS `clonefile` gives a copy-on-write clone, so the disk copy should cost almost nothing. Confirm with `time`. |

### Follow-up start-ups: Tart suspends, lume does not

This is the sharpest split between the two tools, and the subcommand lists prove it.

- **Tart carries a `suspend` subcommand.** `Sources/tart/Root.swift` appends it only on macOS 14 and
  later. It saves the machine state, so a later start restores instead of a full boot. The exact
  restore command and the restore time stay **unverified** — measure both.
- **lume carries no suspend.** Its lifecycle verbs are `run`, `stop`, `shutdown` and `restart`. So
  every follow-up start pays a full macOS boot.

A loop that starts a guest many times should prefer Tart. A test that must start at hour zero needs
lume, and it pays the boot every time.

### Control surfaces, verified from the subcommand lists

| Need | Tart | lume |
|---|---|---|
| Run a command in the guest | `tart exec` — no SSH needed | `lume ssh <vm> '<cmd>'`. Defect #1514 drops piped stdin; #1513 corrupts binary stdout. Fall back to plain `ssh`. |
| Find the guest address | `tart ip` | `lume get`, `lume ls` |
| HTTP API for a harness | none | **`lume serve`**, a local API server. `cua` drives this. |
| Machine-readable docs for a harness | none | **`lume dump-docs`**, CLI and API documentation as JSON |
| Copy a guest | `tart clone`, plus `import` and `export` | `lume clone`, plus OCI `pull` and `push` |
| Change CPU, memory or disk | `tart set` | `lume set` |
| Toggle SIP in the guest | none | **`lume sip`** |
| Prepare the unattended install | none | **`lume setup`** |
| GUI or console view | `--vnc-experimental`, plus `--no-pointer` and `--no-keyboard` | `lume attach` |

This table is the real reason to keep both tools. Tart gives the fast repeat and a no-SSH `exec`.
lume gives the from-IPSW install, an HTTP API, a SIP switch, and JSON docs a harness reads directly.

## Blockers

### Repo-side — these stop a guest before any test runs

1. **The `git+ssh://` homebrew tap input.** `modules/universal/default.nix:217-232` derives
   `nix-homebrew.taps` from **every** `brew-tap--*` input, so a Darwin host build forces all of
   them. One public input at `flake.nix:14` uses `git+ssh://`. A guest with no SSH key stops here.
   Checkpoint 001 item 6 already asks for the one-line fix at
   `generalization-001-slots-sharing-readiness.md:199-207`.
2. **The creator's macOS account.** Without an override, a Darwin host build wants the creator's
   `/Users/<name>` and a matching `system.primaryUser`. nix-darwin does not synthesize `home` or
   `uid` for a macOS-created user, so Home Manager evaluates `home = null`. The only working
   override example lives on the fork chain, so a public deliverable cannot cite it.
3. **sops decryption fails in a fresh guest.** A new guest has a different
   `/etc/ssh/ssh_host_ed25519_key`, so its age recipient is absent from the unattended sops file.
   The escape hatch `kdn.security.secrets.allow = false` exists at
   `modules/universal/security/secrets/default.nix:13-21`, but no adopter-facing doc names it.
4. **`stylix.image` defaults to a personal host.** `modules/universal/_stylix.nix:39-45` fetches a
   fixed-output image from the creator's server. No doc names the override.
5. **`checks/` cannot host this test.** All four checks are `runCommand` derivations. A macOS guest
   needs a Hypervisor entitlement, a network and a writable disk image. The Nix sandbox grants none
   of the three.
6. **No repo script boots a guest.** `darwin-rebuild.sh` and `nixos-rebuild.sh` both target a
   machine that already runs, over SSH. Their `remote=` discovery probes four private DNS search
   domains that a throwaway guest does not resolve.

### Environment — these bound the design

7. **Apple permits two extra concurrent guests per Mac.** Test parallelism cannot exceed that.
8. **VirtioFS read-write mounts corrupt data**, git repositories in particular (openai/tart #1271,
   open since 2026-06-18). Move the closure with `nix copy`, never a `--dir` share.
9. **The Keychain blocks `tart login/clone/pull/push` over plain SSH.** Run `security
   create-keychain` and `security unlock-keychain` before any VM starts.
10. **`tart clone` auto-prune can evict the base image mid-run.** Set `TART_NO_AUTO_PRUNE`.
11. **The macOS installer needs a display device present**, even headless. `--no-graphics` covers it.
12. **The upstream work is not usable.** nixpkgs #429189 is a stalled draft; nix-darwin #1552 has
    zero comments.
13. **A macOS guest cannot run a nested virtual machine. This limit is permanent.** Apple exposes
    `isNestedVirtualizationEnabled` on `VZGenericPlatformConfiguration` only, the Linux-guest
    platform class. The property does not exist on `VZMacPlatformConfiguration`. Tart agrees from
    the other side: `--nested` reads "Enable nested virtualization if possible" and it rejects a
    macOS guest. So `nix-rosetta-builder`, which drives `limactl` and therefore a Linux virtual
    machine, never starts inside a macOS guest. The guest OS is the limit, not the host chip.
    Confirmed from inside the guest on 2026-09-10: `kern.hv_support: 0`, `kern.hv_vmm_present: 1`.

14. **A Nix-built `ssh` cannot reach a lume guest on macOS 26.** Verified 2026-09-10.
    `/usr/bin/ssh` connects. The Home Manager `ssh` and a Nix `bash` `/dev/tcp` both get
    `No route to host`, while `/usr/bin/nc` connects to the same address and port and prints the
    banner. So the fault is **per binary**, not per route. The likely cause is macOS local-network
    privacy, and that cause is **unverified**.

    Consequence for the harness: pin `/usr/bin/ssh` explicitly. Never let a `devenv` shell's `PATH`
    choose the `ssh` for a guest call. Two lume defects push the same way — **#1514** drops piped
    stdin through `lume ssh` (verified: `echo 'echo PIPED_OK' | lume ssh rehearse 'bash -s'` prints
    nothing and exits 0), and **#1513** corrupts binary stdout (verified: 64 zero bytes return as
    65). So the harness uses `/usr/bin/ssh` for every command, and `lume ssh` for none.

15. **lume's own SSH health check fails on a healthy guest**, so `lume create --unattended` deletes
    a guest that works. Split the call: `lume create`, then `lume setup`. `lume setup` has no
    cleanup path, so the guest survives its failure. Treat the `lume setup` exit code as noise, and
    probe SSH yourself.

## Work items

### Phase 1 — unblock the repo (public chain)

- [ ] Change the `git+ssh://` homebrew tap input at `flake.nix:14` to a `github:` URL. The target
      repository is public and `git ls-remote https://…` succeeds with no key.
- [ ] **Re-grade gap 12 in the hub.** [generalization-plan.md](../generalization/definition.md) grades the
      input closure as "hygiene, not a blocker". That grade is correct for an adopter who only
      evaluates slots. It is **wrong** for a fresh-guest Darwin build, which forces every tap input.
      Record both readings; the hub records only one today.
- [ ] Write a public override example for the username and the `uid`.
- [ ] Document `kdn.security.secrets.allow = false` for an adopter.
- [ ] Document a `stylix.image` override for an adopter.
- [ ] Prefer the cheapest guest path where possible: call `mkSlots` directly and never touch
      `modules/universal`. That path avoids blockers 1 to 4 completely.

### Phase 2 — build the harness

- [ ] Put the harness behind a flake **app**, modeled on `apps.jj-experiments-run` at
      `flake.nix:453-476`. Do **not** put it behind `nix flake check`.
- [ ] Make the harness pass a full address or an IP to `darwin-rebuild.sh`, never a bare host name.
- [ ] Call `/usr/bin/ssh` by absolute path for every guest command. Blocker 14 makes a Nix `ssh`
      unusable, and blockers 14 and 15 make `lume ssh` unusable.
- [ ] Split the lume cold path into `lume create` plus `lume setup`, and ignore `lume setup`'s exit
      code. Probe SSH yourself with a 60 s budget — 10 s is the measured cost.
- [ ] Bake the golden image: `tart clone`, `tart set --disk-size 120`, run with `--no-graphics`,
      then poll `tart ip` and port 22.
- [ ] Poll `df -k /` to wait for the APFS container grow. Never poll `diskutil` — it queues on
      `diskmanagementd` and deadlocks against the guest agent.
- [ ] Rename `/etc/{bashrc,zshrc,zshenv,zprofile}` to `*.before-nix-darwin`, and move the image's
      own `~/.zprofile` and the `~/.profile` symlink aside.
- [ ] Add one `trusted-users` line for `nix copy`, then revert `/etc/nix/nix.conf` so it matches
      `knownSha256Hashes`.
- [ ] Build the closure on the host, `nix copy --to ssh-ng://` into the guest, then
      `nix-env -p /nix/var/nix/profiles/system --set` and `$target/activate`.

### Phase 3 — run the real tests

- [ ] Run the hard exit rows in the guest. Cite each row by its criterion text, never by a line
      number — the line numbers move.
      - Guest: 002's scratch-flake evaluation and its no-SSH-agent repeat; both runbook rows of 003;
        both rows of 009.
      - **Bare metal only:** 002's "a real `x86_64-linux` derivation builds through the Rosetta
        builder". Blocker 13 puts it out of reach of every macOS guest.
- [ ] Verify the 8 unverified caveats of checkpoint 003 in the guest.
- [ ] Keep Pattern V1, the drvPath equality gate, on the warm host. Give the guest the activation
      tests only. A cold guest has no warm store, and the gate costs 93 s per warm Darwin host.

### Phase 4 — upstream hygiene

- [ ] Send a nixpkgs pull request that bumps `tart` and corrects the license to `FSL-1.1-ALv2`. Add
      a `.flake.patches/` entry in the meantime.

## Open questions to settle by measurement

- [x] Boot to exec-ready wall clock. **Answered for lume on 2026-09-10: 10 s and 11 s.** The Tart
      number stays unmeasured.
- [ ] Does `lume create --unattended` fail independently of the download path? Rerun the exact
      run-1 command with the cached IPSW — about 9 minutes, no download. This is the most useful of
      the seven unverified items in [lume.research.md](lume.research.md).
- [ ] `tart suspend` and its restore: does it accept a macOS guest, what restores it, and what does
      a restore cost? This one answer sets the warm-loop budget.
- [ ] `clone` wall clock for both tools. APFS copy-on-write should make it near-free. Confirm it.
- [ ] Does `lume serve` plus `lume dump-docs` beat shell-outs for the harness? The JSON docs exist
      to make a machine-driven client easy.
- [ ] Incremental activation time in a guest for this repository. The closure is 33.0 GB; the
      per-checkpoint delta is unmeasured.
- [ ] Does `nix copy` from the host beat a build inside the guest?
- [ ] Does a **stopped** Tart VM count against Apple's two-guest cap? Third parties say no. No
      primary Apple statement exists.
- [ ] Does Tart phone home? The license and the docs name nothing, but nobody audited the sources.
- [ ] Is `hypervisorsOnDarwin = [ "qemu" "vfkit" ]` real in microvm.nix? The hub records it. One
      research pass **could not find it** in the store copy of the microvm source. Treat the Darwin
      host support as unconfirmed until somebody re-checks.
- [ ] Is Mirage mature enough? It fits best on paper, but it is v0.1, absent from nixpkgs, and has
      no public image registry.
- [ ] Does Lima replace Tart? `limactl start template:macos` does the install and the ssh setup in
      one Apache-2.0 command, but it has no OCI registry.

## Notes for a fresh clone

Route 3 of the `jj-experiments` harness needs a hand-written `checks/jj-experiments/devenv.yaml`
that points `nix-configs` at `path:../..`. `.gitignore:39` allows the **root** `devenv.yaml` only,
so the subdirectory-devenv precedent that checkpoint 001 cites is **not** reproducible from a fresh
clone. Fix that before you rely on it as prior art.

## Out of scope

- `i686-linux`. Rosetta for Linux is x86_64 only, so the builder cannot reach it.
- A GUI or Metal test. Nix evaluation, builds and activation call no Metal API.
- The `darwin-utm-guest` feature flag. It gates a **NixOS** guest on a Darwin host, the opposite
  direction, and no host sets it today.
- Commercial tools. Veertu Anka and Parallels have no free tier for this use.

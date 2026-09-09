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

- [darwin-vm-testing-tart.research.md](tart.research.md) — tool landscape, Tart
  license terms, GPU exposure, Nix-in-guest feasibility, timing budget.
- [darwin-vm-testing-repo-surface.research.md](repo-surface.research.md) — what
  the harness must run, and which check and rebuild surface already exists here.

Both files hold the measured evidence and the citations. This file holds only the decisions, the
blockers and the work.

## Target shape

Bake a golden image once. Then clone, activate and destroy per checkpoint. The one-time cost is a
27.31 GB image pull plus about 40 minutes for the Nix install and the first activation. The warm
loop then costs an estimated 2 to 5 minutes per checkpoint.

Do **not** run the cold path per checkpoint.

## Decisions to make first

| Decision | Options | Why it blocks the rest |
|---|---|---|
| VM tool | Tart ≥ 2.33.0, Mirage, Lima | Each has a different install path and a different image source. |
| Nix installer | Determinate, upstream, Lix | nix-darwin **aborts** when it detects Determinate. |
| Guest scope | public chain only | The fork chain adds four `git+ssh://` inputs a keyless guest cannot fetch. |

Tart relicensed to `FSL-1.1-ALv2` at 2.33.0, and the paid regime is retired. Install it with
`brew install openai/tools/tart`. The nixpkgs package is stale at 2.30.6 and still carries
`license.shortName = "fairsource09"` with `unfree = true`.

With Determinate, set `nix.enable = false;` and `determinateNix.enable = true;`, and import
`inputs.determinate.darwinModules.default`. Without that, activation stops with
`error: Determinate detected, aborting activation`.

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

- [ ] Run the four hard exit rows in the guest: `generalization-002-…:110`,
      `generalization-003-…:126`, `generalization-003-…:127`, `generalization-009-…:102-103`.
- [ ] Verify the 8 unverified caveats of checkpoint 003 in the guest.
- [ ] Keep Pattern V1, the drvPath equality gate, on the warm host. Give the guest the activation
      tests only. A cold guest has no warm store, and the gate costs 93 s per warm Darwin host.

### Phase 4 — upstream hygiene

- [ ] Send a nixpkgs pull request that bumps `tart` and corrects the license to `FSL-1.1-ALv2`. Add
      a `.flake.patches/` entry in the meantime.

## Open questions to settle by measurement

- [ ] Boot to exec-ready wall clock. No source publishes a number.
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

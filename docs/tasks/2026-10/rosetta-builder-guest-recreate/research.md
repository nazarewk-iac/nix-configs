---
type: Research
description: How the nix-rosetta-builder daemon decides to delete and recreate the Lima guest, which config values land in lima.yaml, and the drift measured read-only on anji on 2026-10-16.
task: definition.md
authored_by: agent
timestamp: 2026-10-16T11:05:00+02:00
---

# Fork mechanism and anji observations

Sources:

- Fork: `github:nazarewk/nix-rosetta-builder` rev
  `0f95e61b73e7ac2a1b4c7ad9de76d53330b916ae` (branch `feat/customize-working-directory`; locked in
  `flake.lock` with its `nixpkgs` input redirected to this repo's `nixpkgs`). All `module.nix`,
  `package.nix` and `flake.nix` line numbers below are from that rev, read from the store checkout
  `/nix/store/gqvx6n3cls9p5jnvd2hbgp53x2zhzwyq-source`.
- Repo route on anji: `kdn.darwin.rosetta-builder` (slot `modules/slots/rosetta-builder/default.nix`
  → `inputs.nix-rosetta-builder.darwinModules.default`). `modules/den/aspects/rosetta-builder.nix`
  carries the same mechanism. Only `anji` enables it (`hosts/anji/default.nix:40,159-238`).
- Live host read: `ssh kdn-anji`, read-only commands, 2026-10-16. Nothing was started, stopped or
  deleted.

## 1. The generated lima.yaml

`module.nix:219-249` generates one yaml file with `pkgs.formats.yaml`. Every field and where it
comes from:

| yaml field | source | changes when |
|---|---|---|
| `containerd.user: false` | constant, `module.nix:222` | never |
| `cpus` | `cfg.cores`, `module.nix:224` | `nix-rosetta-builder.cores` edit |
| `disk` | `cfg.diskSize`, `module.nix:226` | `nix-rosetta-builder.diskSize` edit |
| `images[0].location` | `${imageWithFinalConfig}/${imageWithFinalConfig.passthru.filePath}`, `module.nix:230` | **any nixpkgs bump**; any input of the image derivation (section 3) |
| `memory` | `cfg.memory`, `module.nix:234` | `nix-rosetta-builder.memory` edit |
| `mounts[0].location` | `${workingDir}/linux-sshd-keys`, `module.nix:236-241` | `nix-rosetta-builder.workingDir` edit |
| `rosetta.enabled: true` | constant, `module.nix:243` | never |
| `ssh.launchdSocketName` | `"Listener"` only when `cfg.onDemand`, `module.nix:246` | `onDemand` edit |
| `ssh.localPort` | `cfg.port`, `module.nix:247` | `port` edit |

The file lives at a `/nix/store/<hash>-rosetta-builder.yaml` path. The hash covers the content,
so one changed line moves the path.

## 2. The consistency check and the delete+recreate

The daemon is the launchd job `rosetta-builderd` (`module.nix:307-408`). Its script runs the check
before every foreground start (`module.nix:352-378`):

```sh
cmp -s ${vmYaml} .lima/rosetta-builder-vm/lima.yaml && \
limactl list -q 2>'/dev/null' | grep -q rosetta-builder-vm && \
find ssh_user_ed25519_key \
  -perm '-go=r' -exec ${boolToString cfg.permitNonRootSshAccess} '{}' '+' \
2>'/dev/null' && \
true || {
  ...regenerate both ssh keypairs, move the public keys into linux-sshd-keys...
  limactl delete --force ${vmName}          # module.nix:374
  limactl create --name=${vmName} ${vmYaml} # module.nix:377
}
exec limactl start --foreground ${vmName}   # module.nix:388
```

`cmp` is a whole-file byte comparison. Every condition that forces delete+recreate:

1. **Any byte difference between the generated yaml and the stored instance yaml.** In practice:
   the `images[0].location` line on every nixpkgs bump, or any edit to `cores`, `memory`,
   `diskSize`, `port`, `workingDir` or `onDemand`.
2. **The instance is not in `limactl list`** (first run, or a manual delete). Note the order: the
   branch still runs `limactl delete --force` on a name that does not exist before it creates.
3. **The user SSH key `ssh_user_ed25519_key` is group- or other-readable while
   `permitNonRootSshAccess` is false** (anji: false, so `-exec false`), or that key file is
   missing (`find` fails, stderr suppressed).

The branch is all-or-nothing: it also rotates both SSH keypairs and rewrites
`ssh_known_hosts` (`module.nix:358-372`), then destroys the disk and creates a fresh instance.
There is no partial reconcile: lima's `vz` driver cannot change cpus, memory or an existing
image after create, which is why upstream chose delete.

## 3. What moves the image store path

`flake.nix:37-40` builds `darwinModules.default` around `image = self.packages.<linuxSystem>.image`
(`flake.nix:22-26`), a `callPackage` of `package.nix` against the flake's `nixpkgs` input — which
this repo redirects to its own `nixpkgs` (`flake.lock`: `"nix-rosetta-builder": {"inputs":
{"nixpkgs": ["nixpkgs"]}}`). The image is the full NixOS system derivation
`imageConfig.config.system.build.images.qemu-efi` (`package.nix:29-206`), an aarch64-linux disk
image built from the host's locked nixpkgs.

`module.nix:178-183` overrides it once more per activation:

```nix
imageWithFinalConfig = image.override {
  inherit debugInsecurely;                       # constant false, module.nix:176
  onDemand = cfg.onDemand;                       # baked into the guest: logind IdleAction, package.nix:84-87
  onDemandLingerMinutes = cfg.onDemandLingerMinutes;
  potentiallyInsecureExtraNixosModule = cfg.potentiallyInsecureExtraNixosModule;
};
```

So the store path, and with it the yaml, changes on:

- any nixpkgs bump (outPath hash and the version string in the qcow2 file name
  `nixos-image-efi-qcow2-<version>-aarch64-linux.qcow2`);
- an edit to `onDemand`, `onDemandLingerMinutes`, `debugInsecurely`, or
  `potentiallyInsecureExtraNixosModule`;
- the repo wrapper's `guest.minFree` / `guest.maxFree`, which feed exactly that last option
  (`modules/slots/rosetta-builder/default.nix:61-67,176-178`) — this is the trap the comment at
  `hosts/anji/default.nix:227-228` warns about;
- a change to the fork's `package.nix` / `constants.nix` (a new fork rev).

Nothing about the guest *disk* enters the yaml: lima copies the image to `basedisk` at create.
After create, the stored yaml only names the image for a future recreate, so a mismatch on that
line destroys a healthy guest without ever re-reading the new image.

## 4. Measured on anji (read-only, 2026-10-16)

- Unit shape (`/Library/LaunchDaemons/org.nixos.rosetta-builderd.plist` via `plutil -p`):
  `UserName=_rosettabuilder`, `WorkingDirectory=/anji-ext-01/rosetta-builder`,
  `KeepAlive=false`, `Sockets.Listener` on `localhost:31122`. The job is wrapped behind
  `/usr/local/bin/kdn-nix-bootstrap run rosetta-builderd`; the job spec lives at
  `/etc/kdn/nix-bootstrap/jobs/rosetta-builderd.json`. Its command resolves to
  `/nix/store/zygffsks22a15mlw8v0cajhmfwgjl0cg-rosetta-builderd-start`, which compares against
  `/nix/store/j7cdzcff75l6byq9p5hm9ws7da7z0gdr-rosetta-builder.yaml`.
- Stored instance dir (`sudo -n ls -la .../.lima/rosetta-builder-vm/`): `lima.yaml` mtime
  Oct 15 16:46 — the cutover recreate. `basedisk` 2.56 GB Oct 15 16:47, `diffdisk` sparse 1 TiB,
  `cidata.iso` and boot logs Oct 15 18:13. The guest started at 18:13 **without** rewriting
  `lima.yaml`: with the lima fork in use (lima 2.2.0, `lima-version` file), create stores the
  yaml verbatim and start never rewrites it, so `cmp` can pass byte-for-byte on later starts.
- Stored yaml content vs generated yaml of the deployed generation: `diff` empty. The current
  repo (working tree, same `flake.lock`) evaluates the image to the exact same path:
  `nix eval --impure --expr 'let f = builtins.getFlake (toString ./.); in (f.inputs.nix-rosetta-builder.packages.aarch64-linux.image.override { debugInsecurely = false; onDemand = true; onDemandLingerMinutes = 180; potentiallyInsecureExtraNixosModule = { }; }).outPath + " / " + ....passthru.filePath'`
  → `/nix/store/kfxv598rx3rsvhadj2wacznnh53xx1z9-nixos-disk-image / nixos-image-efi-qcow2-26.11.20261011.7fd4004-aarch64-linux.qcow2`.
  So **today there is no drift**: the guest survives restarts until the next bump moves the path.
- The cutover finding "0908 image vs 1011 config": the stored yaml then named a September 8 image
  path, the activated October 11 configuration named the path above, `cmp` failed, and the daemon
  recreated at 16:46.

## 5. When the check runs, and what it costs

The check runs on every `rosetta-builderd` process start: host boot, a launchd job reload at
activation (nix-darwin stops and restarts the job when the job definition changes), and every
socket wake while the VM is down (`onDemand=true` path). While the VM runs, `limactl start
--foreground` (`module.nix:388`) keeps the single daemon process alive, so the check does not
re-run.

Consequences:

- **Frequency:** one recreate per nixpkgs bump (or per resource edit), on the first daemon start
  after the activation that carries the new yaml. Not once per boot.
- **Loss:** the whole guest disk — every store path the guest built or fetched. First builds
  afterwards are cold; `builders-use-substitutes` recovers only what public caches hold
  (`modules/slots/rosetta-builder/default.nix:169`).
- **Interruption:** an in-flight build dies. The job reload itself kills the daemon; the VM
  process is its child (`limactl start --foreground`). If the yaml also changed, the new process
  then runs `limactl delete --force` (`module.nix:374`) on the stopped instance. The job-reload
  kill is inferred from the plist shape, not yet measured.
- **Key rotation:** the recreate regenerates both SSH keypairs and rewrites `ssh_known_hosts`
  (`module.nix:358-372`). Self-consistent, so clients see a changed host key on next connect.

## 6. What is not a trigger

- `kdn.darwin.rosetta-builder.guest.diskSizeMax` — an assertion ceiling only
  (`modules/slots/rosetta-builder/default.nix:73-94,180-196`). It enters no yaml.
- `permitNonRootSshAccess` — only a `chmod` outside the guarded block (`module.nix:384-386`).
- The guest's own state, disk usage, or nix version inside the guest.
- lima's own files (`cidata.iso`, `cloud-config.yaml`, `ssh.config`) — regenerated at start,
  never compared.

## 7. Candidate fixes

1. **Stable image reference (best).** Have the yaml name a mutable path under `workingDir` — for
   example `${workingDir}/image/current.qcow2` — and make the daemon refresh that copy (or symlink)
   only at first create. Patch: `module.nix:228-232` plus a copy step before `limactl create`.
   A nixpkgs bump then changes no yaml byte, criterion 1 passes, and the guest keeps its store.
   Guest OS refreshes become an explicit act (delete the copy, or a version stamp the daemon
   checks once). Downside: a silently stale guest OS until someone refreshes it; the image copy
   costs disk once (the 2.56 GB basedisk already costs it).
2. **Pin the image to its own nixpkgs input.** Fork `flake.nix`: build `package.nix` from a
   dedicated `imageNixpkgs` input instead of the shared one. Host bumps move no yaml; moving the
   guest OS is one deliberate input bump (which then recreates — intended). Downside: a second
   nixpkgs in the lock that ages.
3. **Warn-only reconcile.** Change the `||` branch: on a yaml mismatch the daemon prints a diff
   summary and exits instead of `limactl delete --force`; a separate one-shot
   (`rosetta-builder-recreate`) does what the branch does today. Safety net for any remaining
   volatile field, at the cost of the builder staying down until an operator acts.

Recommended: 1, with 3 as the policy for any future mismatch. 2 is the cheapest stop-gap if the
fork must stay untouched.

## 8. Re-verify with

```sh
# stored yaml vs generated yaml of the deployed generation (read-only on anji):
ssh kdn-anji 'sudo -n cat /anji-ext-01/rosetta-builder/.lima/rosetta-builder-vm/lima.yaml'
ssh kdn-anji 'cat /nix/store/j7cdzcff75l6byq9p5hm9ws7da7z0gdr-rosetta-builder.yaml'
# what the current tree generates for the image location:
nix eval --impure --expr 'let f = builtins.getFlake (toString ./.); i = f.inputs.nix-rosetta-builder.packages.aarch64-linux.image.override { debugInsecurely = false; onDemand = true; onDemandLingerMinutes = 180; potentiallyInsecureExtraNixosModule = { }; }; in i.outPath + "/" + i.passthru.filePath' --raw
```

After the next flake update, re-run the third command: if it moves, the yaml moved, and the first
daemon start will recreate the guest.

## 2026-10-18 live investigation

Live investigation on `anji` (macOS 27.0.1). The guest sshd never comes up. Two **independent**
defects cause this. Either one alone stops provisioning.

### Defect 1 — launchd PATH drops `/usr/bin` from first position

The fork's module builds the launchd job `PATH` without `/usr/bin` first. Lima's guest bootstrap
then runs the nixpkgs `openssh` (built without GSSAPI) to provision the guest. That ssh rejects
lima's `-o GSSAPIAuthentication=no`, so the provisioning ssh dies and the guest sshd never comes
up.

- **Fix:** `launchd.daemons.rosetta-builderd.path = lib.mkBefore [ "/usr/bin" ]` in
  `hosts/anji/default.nix`.
- **Verified:** the eval'd `PATH` starts with `/usr/bin` and matches a live plist edit
  byte-for-byte.

### Defect 2 — socket-activation `ESRCH`

The daemon is re-homed behind `kdn-nix-bootstrap` (that wrapper holds the Full Disk Access grant).
With the default `onDemand = true`, lima calls `launch_activate_socket("Listener")` from
`limactl hostagent`. That process is a **grandchild** of the wrapper.

launchd resolves the socket by the calling process's job. The grandchild has a different bootstrap,
so the call fails with `ESRCH` ("no such process"). The hostagent then exits ~19 s into every
start:

```
ha.stderr.log: Driver stopped due to error: "launchd socket \"Listener\" failed to activate: no such process"
```

launchd respawns it, and the VZ guest is torn down and rebooted before it finishes booting.
**Measured:** `runs=132`, one cycle per ~19 s. The wrapper's own comment that claims socket
activation survives was measured on the non-`onDemand` path.

- **Fix:** `nix-rosetta-builder.onDemand = false` — this drops `Sockets.Listener` and sets
  `KeepAlive = true`. Also force-clear the empty `Sockets` key the fork leaves behind:
  `launchd.daemons.rosetta-builderd.serviceConfig.Sockets = lib.mkForce { }`. The fork sets
  `Sockets."Listener" = optionalAttrs cfg.onDemand {...}`, which with `false` renders an empty
  `<dict/>`.

### Note for the fork

This fixes the daemon lifecycle only. A fork fix should **drop** the `Sockets` key entirely instead
of emptying it.

### Activation attempt (blocked)

A `nix run '.#darwin-rebuild' -- switch remote=anji` was attempted and **failed after 1h48m**: the
remote builder `briv.lan` ran out of disk space while building the aarch64-linux NixOS guest image:

```
cat: write error: No space left on device    # /nix/store/...-nixos-disk-image.drv
```

`onDemand = false` changes the guest image (`logind` `IdleAction` is baked into it), so the image
genuinely rebuilds. The switch must be re-run after freeing disk on `briv`. `anji` is still on the
previous generation; the live plist is hand-patched to the intended state but the daemon is not
loaded.

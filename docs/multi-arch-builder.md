---
type: How-To
description: Set up a dual-arch (aarch64-linux + x86_64-linux) Nix builder on this Apple Silicon nix-darwin host, keeping a single authoritative /nix/store.
timestamp: 2026-07-30T16:14:54+02:00
---

# Dual-arch Linux builder on Apple Silicon (nix-darwin)

> **Agent summary:** implement one of the options below so this `aarch64-darwin` host can
> build **both** `aarch64-linux` and `x86_64-linux` derivations locally, while keeping a
> single authoritative `/nix/store` on the host. This is a handover doc — it presents all
> viable options with tradeoffs so the implementer picks; it does not prescribe a single path.
> Companion doc: [multi-arch-container-builder.md](./multi-arch-container-builder.md) (how the
> two arches get stitched into one OCI image index once this is in place).

---

## Goal & current state

**Goal.** `nix build` (and container-image builds) for **both** Linux arches from this Mac,
without cloud CI, and **without maintaining a second full Nix store** — the host
`/nix/store` stays the single source of truth; builders are disposable.

**Target host** is an `aarch64-darwin`, nix-darwin-managed Apple Silicon workstation (referred to
below as `<workstation>` — substitute its `hosts/<workstation>/default.nix`). It has Rosetta 2
installed including the Linux runtime (`/Library/Apple/usr/libexec/oah` contains `RosettaLinux`),
so Rosetta-backed x86_64-linux is available without extra host setup.

**What already exists in this repo:**

- `hosts/<workstation>/default.nix` — enables the stock builder:
  ```nix
  nix.linux-builder.enable = true;
  nix.linux-builder.ephemeral = true;   # qcow2 wiped on every restart → already stateless
  ```
- `hosts/anji/default.nix` + `hosts/anji/linux-builder.nix` — a **much** more customized builder
  on the `anji` host: a hand-rolled `nix.linux-builder.package` (imports
  `nixos/modules/profiles/nix-builder-vm.nix`), `nix.linux-builder.config` deferred module with
  `virtualisation.darwin-builder.{diskSize,memorySize,min-free,max-free}` + `virtualisation.cores`,
  and a manual `nix.buildMachines` entry with a base64 `publicHostKey`. **This is the reference
  for how far the builder can be customized** and the exact hook (`nix.linux-builder.config`) that
  Options B/C below plug into.
- `modules/universal/profile/remote-builders/default.nix` — `kdn.profile.remote-builders`, builds
  `nix.buildMachines` from a static list. Note line ~104:
  `(builtins.filter (builder: !(builtins.elem "x86_64-linux" builder.systems)))` with a
  `# TODO: implement the most common "x86_64-linux" builder properly` — **x86_64-linux remote
  builders are currently filtered out**; this work is that TODO.
- `modules/universal/nix/remote-builder/default.nix` — `kdn.nix.remote-builder` (localhost builder
  option, ssh identity, `localhost.systems` defaulting to `pkgs.stdenv.hostPlatform.system`).
- `modules/universal/nix.nix` — global `nix.settings` (`substituters`, `trusted-public-keys`,
  `trusted-users`). This is where a host-as-cache substituter (see "Sharing the store") would be
  wired for the host side.

Current `/etc/nix/machines` on this host (single arch):

```
ssh-ng://builder@linux-builder aarch64-linux /etc/nix/builder_ed25519 1 1 kvm,benchmark,big-parallel - <base64hostkey>
```

---

## Background: why the store is *already* single & how transfer works

Understanding this decides most of the design. In **remote-builder** mode (what
`nix.buildMachines` / `nix.linux-builder` set up), the host daemon drives everything:

1. Host evaluates → `.drv` in the **host** store.
2. Host checks its store + substituters. **Remote builders are not substituters** — Nix never
   asks a builder "do you already have this output?".
3. Host ensures all build **inputs** are valid in the **host** store first (building/fetching
   locally as needed) — *before* it picks a builder.
4. Host ensures the builder has the inputs: with `builders-use-substitutes = true` the **builder**
   fetches missing inputs from its own substituters; anything still missing is uploaded
   host → builder.
5. Builder builds.
6. On success, Nix copies the output **+ its runtime closure back to the host store**.

**Consequences that matter here:**

- After step 6 the full closure lives on the **host**. The builder store is pure scratch —
  **correctness never requires it to persist anything**, which is exactly why
  `nix.linux-builder.ephemeral = true` (already set on this host) is safe.
- Transient duplication is unavoidable *during* a build (inputs exist in both stores while
  building), but it's one in-flight closure, not a second full store, and it's gone on VM restart.
- The host store accumulates build **inputs** even for remote builds (step 3). For a
  "single authoritative store" that's desirable — the host is the source of truth.

Sources: <https://nix.dev/manual/nix/2.25/advanced-topics/distributed-builds>,
<https://docs.nixbuild.net/remote-builds/index.html>,
<https://nix.dev/tutorials/nixos/distributed-builds-setup.html>.

---

## Options (pick one)

All produce working `aarch64-linux` + `x86_64-linux`. They differ in speed, how much new
machinery, and how far they diverge from the current `nix.linux-builder` setup.

### Option A — binfmt/QEMU emulation inside the existing VM  *(zero new deps, slowest x86)*

Add x86_64 emulation to the **existing** aarch64 builder VM via the `nix.linux-builder.config`
deferred module, and advertise both systems.

```nix
# in the host config (e.g. hosts/<workstation>/default.nix), on the existing builder block:
nix.linux-builder.systems = [ "aarch64-linux" "x86_64-linux" ];
nix.linux-builder.config = {
  # `boot.binfmt.emulatedSystems` also configures Nix's `extra-platforms` inside the VM.
  boot.binfmt.emulatedSystems = [ "x86_64-linux" ];
};
```

- **Pros:** no flake input, no new VM, purely declarative with what's already here. Works today.
- **Cons:** x86_64 runs under **qemu-user TCG** software emulation — ~2.5× slower than Rosetta on
  compile-bound work. QEMU on macOS **cannot** use Rosetta, so this path is capped at emulation
  speed. One VM shared by native + emulated builds (keep the Nix sandbox on to isolate).
- **Note:** just adding `"x86_64-linux"` to `systems` **without** the binfmt line does nothing
  (confirmed in nix-darwin#1192).

Sources: <https://github.com/nix-darwin/nix-darwin/issues/1192>,
<https://search.nixos.org/options?show=boot.binfmt.emulatedSystems>,
<https://github.com/NixOS/nixpkgs/issues/262941>.

### Option B — `applicative-systems/vzvm`: Rosetta-backed, drop-in `package` swap  *(recommended: smallest diff)*

A Virtualization.framework backend that is a **drop-in** for `nix.linux-builder`: same port, same
host key, same options. One aarch64 VM, Rosetta exposed → near-native x86_64-linux.

```nix
# flake.nix inputs:
#   vzvm.url = "github:applicative-systems/vzvm";
# then in the host config:
nixpkgs.overlays = [ inputs.vzvm.overlays.default ];   # wire inputs through kdnConfig as usual
nix.linux-builder = {
  enable = true;
  package = pkgs.darwin.linux-builder-vz;              # vz + Rosetta backend
  systems = [ "aarch64-linux" "x86_64-linux" ];        # the x86 line is required or Rosetta is unused
  ephemeral = true;                                    # keep the existing stateless behavior
};
```

- **Pros:** minimal change to the current `nix.linux-builder` setup; keeps port/host key so no
  `/etc/nix/machines` surgery. Rosetta x86 ~2.5× faster than QEMU; native aarch64 unchanged; host
  closure smaller (no QEMU).
- **Cons:** it's an **overlay, not upstreamed** — a new external input to track. First rebuild is
  slow (old builder compiles the new guest, vzvm builds from source). **Migration:** vzvm writes a
  **raw** image, not qcow2 — delete the old data disk first:
  `sudo rm -f /var/lib/linux-builder/nixos.qcow2` (adjust to `nix.linux-builder.workingDirectory`).
- **Requirements:** `aarch64-darwin`, macOS 13+, Rosetta (already installed here).
- **Honesty caveat vzvm states:** the 2.5× headline is one compile-bound workload (`zstd`,
  Rosetta's best case); `openssl` was ~7% *slower*; SIMD-heavy x86 (ffmpeg) untested.

Source: <https://github.com/applicative-systems/vzvm>.

### Option C — `cpick/nix-rosetta-builder`: Rosetta-backed, standalone module  *(recommended: most features)*

A separate nix-darwin module (Lima/vz, `rosetta.enabled = true`) that registers **both** systems
from one VM and adds on-demand idle-poweroff + hardening (non-root service account, loopback-only,
non-public host key).

```nix
# flake.nix inputs:
#   nix-rosetta-builder.url = "github:cpick/nix-rosetta-builder";
# then in the host config:
imports = [ inputs.nix-rosetta-builder.darwinModules.default ];
nix-rosetta-builder = {
  onDemand = true;          # power off VM when idle
  # cores / memory / diskSize / onDemandLingerMinutes / speedFactor available
};
# It hardcodes systems = [ <hostLinux> "x86_64-linux" ] into nix.buildMachines.
```

- **Pros:** dual-arch from one VM with Rosetta; on-demand shutdown; better security defaults; the
  cleanest match to the "disposable builder, host is source of truth" goal.
- **Cons:** it replaces / runs alongside `nix.linux-builder` (a bigger conceptual change than
  Option B's `package` swap). **Bootstrap dance:** it needs an existing Linux builder to build
  itself the first time — keep stock `nix.linux-builder` enabled for the first `darwin-rebuild
  switch`, then swap.

Source: <https://github.com/cpick/nix-rosetta-builder>.

### Option D — container-based builders (OrbStack / colima / docker)  *(only if already standardized on containers)*

Run one or two Linux Nix-daemon builders as containers, expose `sshd`, register each in
`nix.buildMachines`. OrbStack runs amd64 Linux via Rosetta (near-native), so it can match Option
B/C speed.

- **Pros:** lightweight (shared kernel); OrbStack gives Rosetta x86.
- **Cons:** loses declarative `nix.linux-builder` integration; more manual moving parts (Nix
  install per machine, ssh keys, keeping them running). Only worth it if OrbStack/colima is
  already in the toolchain.

Sources: <https://docs.orbstack.dev/machines/>, <https://github.com/abiosoft/colima>.

### Option E — two separate `nix.linux-builder` instances  *(not recommended)*

Both cached builder images default to `hostPort = 31022`, and you can't build a custom-port image
until you already have a builder — bootstrapping two is a fragile, multi-step dance (often needs
`--option sandbox false`). Prefer **one dual-arch VM** (A/B/C). Documented failure mode:
nix-darwin#1192.

---

## Sharing the store / binary cache (independent of the option above)

The remote-builder flow already keeps the host store authoritative and copies results back
automatically (see Background). Two knobs + one optional service refine how deps move:

### 1. `builders-use-substitutes` — always turn this on

Makes the **builder** pull inputs from its own substituters (public caches) instead of the host
uploading everything over the slow VM link. The nixpkgs darwin-builder docs literally note it
*"will reduce your disk utilization"*.

```nix
# host side, alongside the other nix.settings (see modules/universal/nix.nix):
nix.settings.builders-use-substitutes = true;
```

### 2. Keep the builder store disposable

- `nix.linux-builder.ephemeral = true` (already set here) wipes the qcow2 on restart. Option C's
  on-demand poweroff achieves the same statelessness.
- The `nix-builder-vm.nix` profile already runs guest auto-GC via `virtualisation.darwin-builder.{min-free,max-free}`
  (see `hosts/anji/default.nix` for a worked example: `min-free = 0.1*disk`, `max-free = 2*min-free`).
  Leave `keep-outputs`/`keep-derivations` **off** on the builder. Size `diskSize` to hold the
  largest single build closure so GC can't starve a build.
- **Alternative — RAM-backed store:** `virtualisation.darwin-builder` sets
  `writableStoreUseTmpfs = false` by default (disk-backed, persistent across guest restarts). You
  *can* flip it to `true` to back the guest store with tmpfs so it resets each boot — but then the
  store must fit in `memorySize` RAM, usually too small for real builds. Prefer disk-backed +
  `ephemeral`.

### 3. Optional — serve the host `/nix/store` to the builder as a substituter

Only worth it if you frequently rebuild **large local-only** closures (not on any public cache);
otherwise (1) already avoids re-uploading. Pattern (host serves, guest trusts):

```bash
# host: generate a cache signing key once
nix-store --generate-binary-cache-key cache.local-1 \
  /var/secret/cache-priv-key.pem /var/secret/cache-pub-key.pem
```

```nix
# host (nix-darwin): serve the store. Bind to an address the VM can reach
# (QEMU SLIRP gateway is 10.0.2.2 on the stock darwin-builder).
services.nix-serve = {
  enable = true;
  secretKeyFile = "/var/secret/cache-priv-key.pem";
  # bindAddress / port, e.g. 0.0.0.0:5000
};
```

```nix
# guest builder config (via nix.linux-builder.config — see hosts/anji for the pattern):
nix.settings = {
  substituters = [ "http://10.0.2.2:5000" "https://cache.nixos.org" ];
  trusted-public-keys = [
    "cache.local-1:<contents of cache-pub-key.pem>"          # MANDATORY or guest rejects host paths
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];
  builders-use-substitutes = true;
};
```

`trusted-public-keys` is mandatory — the guest refuses unsigned/untrusted paths; `nix-serve` signs
with `secretKeyFile`. This repo already has a `nix-serve`-style substituter/`trusted-public-keys`
pattern in `modules/universal/virtualisation/microvm/host/default.nix` to model against.

> **Do NOT add a `post-build-hook` or manual `nix copy`** for the normal flow — the remote-builder
> protocol already copies each output + runtime closure back to the host store. A post-build-hook
> is only for pushing to an *external* cache, which is out of scope here.

Sources: <https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/nix-builder-vm.nix>,
<https://github.com/NixOS/nixpkgs/blob/master/doc/packages/darwin-builder.section.md>,
<https://nix.dev/manual/nix/2.27/advanced-topics/post-build-hook.html>,
<https://github.com/edolstra/nix-serve>, <https://wiki.nixos.org/wiki/Binary_Cache>.

---

## `/etc/nix/machines` mechanics (for reference / Option D)

One line per builder; a single machine advertises multiple arches via a comma-separated systems
field:

```
ssh-ng://builder@linux-builder aarch64-linux,x86_64-linux /etc/nix/builder_ed25519 8 1 kvm,benchmark,big-parallel - <base64hostkey>
#          <user@host>          <systems>                  <sshKey>              <maxJobs> <speed> <supportedFeatures>  <mandatory> <hostKey>
```

Selection: daemon matches derivation `system` against each machine's `systems` and required
features against `supportedFeatures`/`mandatoryFeatures`, then picks by `speedFactor` + free slots
(`maxJobs`). Requires `nix.distributedBuilds = true`. This repo manages the file declaratively via
`nix.buildMachines` (see `modules/universal/profile/remote-builders/default.nix`), so add/extend
entries there rather than editing `/etc/nix/machines` by hand.

Source: <https://releases.nixos.org/nix/nix-2.34.8/manual/advanced-topics/distributed-builds.html>.

---

## Recommendation & implementation notes

For this host (already has the aarch64 VM + `ephemeral = true`, Rosetta installed, wants x86_64,
prefers declarative + near-native):

1. **Option B (vzvm)** if you want the *smallest* change — one input + overlay + `package` swap.
2. **Option C (nix-rosetta-builder)** if you want on-demand idle-poweroff + hardening and don't
   mind the separate module + bootstrap dance.
3. **Option A (binfmt/QEMU)** as a zero-dependency stopgap if x86 build volume is low and you want
   it working *today* without a new flake input.

Regardless of option: set `nix.settings.builders-use-substitutes = true`, keep the builder
`ephemeral`, leave the host store as the single authoritative store (no post-build-hook).

**Wiring conventions for this repo (don't skip):**

- New flake inputs go through the existing `kdnConfig.inputs` / `inputs` plumbing in `flake.nix`,
  not ad-hoc.
- The `# TODO: implement the most common "x86_64-linux" builder properly` filter in
  `modules/universal/profile/remote-builders/default.nix:104` should be revisited — once this host
  builds x86_64 locally, the localhost builder's `localhost.systems` (default
  `[ pkgs.stdenv.hostPlatform.system ]`) may want `"x86_64-linux"` added, and the x86_64 filter
  relaxed for real remote builders.
- The `anji` host is the closest existing precedent for a customized builder (custom `package`,
  `config` deferred module, disk/RAM sizing). Mirror its structure for Option A's `config` block.
- **Validate**: after `darwin-rebuild switch`, confirm both arches build:
  ```bash
  nix build --no-link --impure --expr \
    'with import <nixpkgs> { system = "x86_64-linux"; }; runCommand "x" {} "uname -m > $out"'
  nix build --no-link --impure --expr \
    'with import <nixpkgs> { system = "aarch64-linux"; }; runCommand "a" {} "uname -m > $out"'
  ```
  and check `/etc/nix/machines` lists both systems for the builder.
- `darwin-rebuild switch` is a **host-level** action for the human/owner to run — the implementing
  agent should stage the config and hand back the switch command, not run it unprompted.

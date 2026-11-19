---
type: Task
description: Connect the build farm's arm pool directly to anji's Rosetta builder VM (aarch64-linux) over a LAN port, bypassing the anji darwin host, so aarch64-linux builds (e.g. briv) run on the fast VM instead of failing on the darwin host or crawling on the Pi. Includes a dedicated SOPS-stored SSH key for VM access.
status: open
authored_by: agent
timestamp: 2026-11-09T20:10:00+01:00
---

# Build farm: reach the Rosetta VM directly (not through anji's darwin proxy)

## Why

`arm` pool → `buildfarm-arm` (anji). anji is `aarch64-darwin`; it can only build aarch64-linux by
forwarding to its local Rosetta VM. On the trusted/`buildDerivation` path that forward is skipped, so
an aarch64-linux kernel-source **FOD with a non-FOD aarch64-linux dependency** fails on anji
(`a 'aarch64-linux' … required … but I am 'aarch64-darwin'`) — the `docs/lix-caveats.md` edge. That
is why `briv` cannot be built through the farm and it either fails or is pushed to the slow Pi.

Fix: expose the **Rosetta VM's sshd on an anji LAN port** and point the `arm` pool straight at it, so
the pool has a real `aarch64-linux` endpoint and no darwin host is in the path.

## Current facts

- The VM is `nix-rosetta-builder`; its sshd is forwarded by lima to **`127.0.0.1:31122`** on anji
  (`nix-rosetta-builder.port = 31122`; `lima` user-mode networking, host-local only).
- `data/build-farm.nix`: `builders.anji.address = anji.lan…` (one `port`, default 22), and `anji` is
  in **two** pools (`arm` and `darwin`). A builder has a single port, so the darwin-pool `anji:22`
  cannot also be the VM port → the VM needs its **own** builder entry (`anji-arm`).
- The VM accepts builds from build-farm clients (it runs `kdn.profile.remote-builders` → the
  `kdn-nix-remote-build` account + client signing keys).
- **Measured 2026-11-10:** that second bullet is not true of the deployed image. The upstream guest
  is a single-user appliance: `getent passwd` shows only `builder`, and `nix.conf` has
  `trusted-users = root builder`. HAProxy passes the client's username through unchanged, so every
  farm connection to `anji.lan:31123` dies at key exchange. The pool then marks `anji-arm` down and
  uses the `backup` briv — the SD-card Pi — which is how the `anji` build of 2026-11-10 failed on
  `system-path.drv` with that card full.

## Steps

1. **anji: forward the VM port onto the LAN.** Add a launchd daemon (nix-darwin) that runs
   `socat TCP-LISTEN:<LANPORT>,bind:<anji-lan-ip>,reuseaddr,fork TCP:127.0.0.1:31122`, and open
   `<LANPORT>` in the darwin firewall for the LAN only. `<LANPORT>` = a fixed, documented port
   (e.g. `31123`), reachable on `anji.lan` and (optionally) the NetBird mesh like the other pools.

2. **Dedicated SSH key for VM access** (stored in SOPS):
   - Generate an ed25519 key `kdn-rosetta-builder` (comment identifies the purpose).
   - Private key → SOPS under the `llms`/builder secrets tree, re-encrypted so **only** the
     build-farm gateway host key (etra) and the **usual two recovery YubiKeys** can decrypt it.
     No other host.
   - Public key → the VM's authorized keys for `kdn-nix-remote-build` (the `hosts/anji/linux-builder.nix`
     remote-builder account), i.e. the VM trusts this dedicated key.
   - **Auth model note (decide here):** HAProxy is TCP-passthrough, so the _client_ authenticates to
     the VM. Either (a) keep the existing per-client `kdn-nix-remote-build` keys trusted by the VM
     (the VM already trusts them) and treat the dedicated key as an additional gateway/recovery
     credential, or (b) make the dedicated key the only key the VM trusts and have the gateway hold
     it. (a) is minimal and works today; (b) is stricter but needs the gateway to be the single
     holder. Record the choice.

     **Decided 2026-11-10 (owner): (a).** The farm's clients already share one key, deployed from
     SOPS as `ssh.kdn-nix-remote-build` (fingerprint `SHA256:xtdXqjc/53ZIhTn4bMquc6pGxQvX3gQKpxM7g7MX1P4`).
     The guest takes its public half, so no new secret is generated and no gateway credential is
     needed. Implemented in `hosts/anji/default.nix` as
     `nix-rosetta-builder.potentiallyInsecureExtraNixosModule`: it declares the
     `kdn-nix-remote-build` account (uid/gid 25839, `isSystemUser`) with that key and leaves
     `allowed-users` at `*`. The account is deliberately **not** a `trusted-user`: a trusted client
     uses `buildDerivation` and can no longer forward to its own builders (`docs/lix-caveats.md`).
     A new image changes `lima.yaml`, so the guest is recreated once.

3. **build farm: add the `anji-arm` builder.**
   - `data/build-farm.nix` `builders.anji-arm = { address = "anji.lan…"; port = <LANPORT>; }`.
   - `pools.arm.builderOrder = [ "anji-arm" "briv" ]` (briv stays the `backup`).
   - Keep `builders.anji` (port 22) only in the `darwin` pool. The build-farm option asserts each
     client's `hostPort`/`systems` maps to a pool — no client change (clients still dial
     `buildfarm-arm`).

4. **Redeploy + verify.**
   - Redeploy anji (`darwin-rebuild`) for the socat + firewall + VM key; redeploy etra for the proxy.
   - From a client: `nix store ping --store ssh-ng://kdn-nix-remote-build@buildfarm-arm` shows the
     VM's nix, not anji's.
   - Build `briv` with the **default** builders (no `--builders`): it must build on the VM (fast) and
     succeed, proving the darwin-host edge is gone. Record the time.

## Acceptance

- `arm` pool resolves to the Rosetta VM (`aarch64-linux`) directly; briv builds via the default farm
  without the `but I am 'aarch64-darwin'` error, and materially faster than the Pi.
- The dedicated key exists in SOPS with only etra + the two YubiKeys as recipients; the VM authorizes
  its public half as `kdn-nix-remote-build`.
- Firewall exposes `<LANPORT>` on the LAN only; no darwin host in the aarch64-linux build path.

## Risks

- `socat` on darwin + the macOS application firewall; verify the bind and the firewall rule.
- The VM's ssh host key changes if the lima guest is recreated (`diskSize`/`lima.yaml` change) — the
  pool uses `StrictHostKeyChecking no`, but note it.
- Redeploying anji recreates the guest only on a `lima.yaml` change; a plain socat/firewall change must
  not hit that path.

## Progress

- 2026-11-10 — steps 1 and 3 are deployed: the socat forward runs as
  `org.nixos.kdn-rosetta-farm-forward` (`0.0.0.0:31123` → `127.0.0.1:31122`) and `data/build-farm.nix`
  carries the `anji-arm` builder. Step 2 now has its decision (model (a)) and the guest-side account;
  the image rebuild, the anji switch, and the end-to-end `nix store ping` / `briv` build are pending.
- Verified from anji: `nix store ping --store ssh-ng://rosetta-builder` answers
  `Version: 2.34.8, Trusted: 1`, so the guest is a healthy builder for its own host. Only the LAN
  path was broken.
- The guest disk is `/dev/vda2`, 1008G with `x-systemd.growfs`, backed by a sparse 1T `diffdisk` on
  `/anji-ext-01`. No resize is needed; `diskSize = "1024GiB"` is already effective.

## Progress — 2026-11-10 (standalone mode)

- The guest is now updated **in place** instead of being recreated. `nix-rosetta-builder` moved to
  the fork branch `feat/in-place-updates` (two commits) and `hosts/anji` sets
  `nix-rosetta-builder.mode = "standalone"`. See
  [docs/multi-arch-builder.md, "Updating the guest in place"](../../../multi-arch-builder.md).
- Why it was needed here, beyond convenience: in `ephemeral` mode the generated `lima.yaml` embeds
  the guest image's store path, so a darwin build depends on an `aarch64-linux` image closure. When
  that image was built on another builder it is unsigned, and `anji` refuses it:
  `cannot add path '…-sshd.conf-final' because it lacks a signature by a trusted key`. The stable
  image path removes the dependency entirely.
- The bootstrap image is out of the host's closure: `nix-rosetta-builder.guest.installImage` builds
  and installs it on demand, and a switch no longer builds a qcow2.
- `anji` itself now builds its aarch64-linux parts on its own Rosetta VM rather than the farm, and
  the guest carries the `kdn-nix-remote-build` account with passwordless sudo for in-place updates.
- Resolved 2026-11-10: the `anji-arm` path works (see the next section). The socat forward had been
  running since 2026-11-09 with a store closure that was later collected, so every per-connection
  `socat1` exec failed to load its libraries.

## Progress — 2026-11-10 (why `anji-arm` stayed DOWN)

`arm_out/anji-arm` was `DOWN` while the guest itself answered on `anji.lan:31123`. Three
independent faults, each sufficient on its own to keep the pool on the `briv` backup:

1. **sshd per-source penalties.** OpenSSH 10 penalises a connection closed before authentication —
   which is exactly the HAProxy `tcp-check` every 10 s. The guest reset every probe
   (`ECONNRESET … at step 1 of tcp-check`). The guest now sets
   `services.openssh.settings.PerSourcePenaltyExemptList = "192.168.5.0/24"`, its own lima network.
2. **The macOS application firewall.** macOS decides per **binary**, and socat had no allowance, so
   LAN connections to 31123 were dropped before socat saw them. A loopback connection bypasses the
   firewall, so every test on the host passed while every other machine failed. The allowance names
   a store path, so a nixpkgs bump revokes it; `system.activationScripts.anji-firewall` re-adds it
   when missing. See [hosts/anji/bootstrap.md, "Firewall"](../../../../hosts/anji/bootstrap.md).
3. **Nix implementation mismatch.** The guest ran CppNix 2.34 while the clients and the other
   builders run Lix 2.95; `ssh-ng` answered `protocol mismatch` before a build was dispatched. The
   fork installs `pkgs.lix` in the guest, which also forces `min-free`/`max-free` to be byte counts
   (Lix rejects the size strings CppNix accepts).
4. **The build account was forced to the wrong protocol.** The `Match` block forced
   `nix-store --serve`, the legacy protocol, while an `ssh-ng` client opens the session with
   `nix-daemon --stdio`. It now forces the daemon and the account joins `trusted-users`, so the
   daemon may add the unsigned paths every build produces. It is still not a shell account: the
   forced command ignores whatever the client asks for, and no TTY or forwarding is allowed.

Two operational details worth remembering:

- `guest.switch` copies with `--no-check-sigs`: the guest's `nix-store --serve` path enforces
  `require-sigs` even for `builder`, who is in `trusted-users` — the daemon path trusts that account
  and the serve path does not. The copy runs over the VM's private console network, so skipping the
  check there is the trust boundary the appliance already relies on.
- Moving a guest from CppNix to Lix in one step fails at `Failed to install bootloader`:
  `switch-to-configuration` installs the bootloader **before** activating `/etc`, so the new Lix
  binary parses the old `nix.conf` and rejects its `min-free`/`max-free` size strings. Run
  `$SYS/activate` first, then `$SYS/bin/switch-to-configuration switch`.

After all four were off the list the proxy still failed, because macOS's firewall keeps its verdict
per process: socat had been running since before the allowance existed, so LAN sessions were
dropped while loopback and the health check worked. One `launchctl kickstart -k` cleared it.

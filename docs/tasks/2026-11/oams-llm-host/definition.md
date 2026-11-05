---
type: Task
description: Turn oams (ASUS ROG laptop, RX 6800M 12 GB, 64 GB RAM) into a second llama-swap host for small GPU models, with ZFS-backed model storage, a GPU-serving toggle that yields to gaming and battery, and registration in the fleet data so LiteLLM can route to it.
status: in-progress
authored_by: agent
timestamp: 2026-11-05T09:49:54+01:00
---

# oams as a second llama-swap host

## Context

`brys` is the only llama-swap host today. Its GPU is a Radeon Pro W6600 (8 GB,
NAVI23), which this repo measured at **158.9 t/s prefill / 24.8 t/s decode** for
`gemma-4-e4b` — while `oams`, a laptop with a Radeon RX 6800M (12 GB, NAVI22),
does **1371.8 / 82.4** on the identical model and llama.cpp build
(see [docs/local-llms.md](../../../local-llms.md#same-models-on-brys-vs-oams-the-card-matters-far-more-than-the-flags-2026-11-05)).
The W6600 is the weaker card; oams is 6-9x faster at prefill and ~3x at decode
for small models.

So the small GPU models belong on oams, not brys. But oams is a **laptop that
also runs a graphical session, Steam, and a build-farm client**, and a resident
model fights all three. The serving must therefore be switchable off without a
rebuild.

This task covers: the ZFS datasets, mirroring brys' llama-swap wiring, the
toggle, and registration in `data/llm.nix`.

## Findings that shape the design

- **oams has no `kdn.disks.persist` bucket model.** It uses raw disko datasets in
  `hosts/oams/disko.nix` (`fs/*` with explicit mountpoints), unlike brys which
  uses `kdn.disks.enable` buckets. New model/session/state directories must be
  declared as disko datasets there, with `systemd.tmpfiles` for modes where
  disko cannot express them.
- **The GPU device id differs**: oams is `1002:73df` (RX 6800M), brys is
  `1002:73e3` (W6600). `swap.vulkanDeviceSelect` must be `1002:73df!` and the
  brys `llm.gpu` block must not be copied verbatim.
- **No power/battery-driven toggle exists.** The build-farm toggle is
  SSID + gaming-scope driven (`data/build-farm.nix`, `modules/den/aspects/build-farm.nix`
  `gamingScopes`), not battery/AC driven. A battery/AC condition is new wiring.
- **Disk**: oams has a 1.8 TB NVMe (9.0 GB/s measured) with 530 GB free,
  ZFS `primarycache=all` + `lz4`.

## Proposed approach

1. **Datasets** in `hosts/oams/disko.nix`: `/var/lib/kdn/llms/models`,
   `/var/lib/kdn/llms/sessions` (0770, group `llama-cpp-sessions`),
   `/var/lib/llm-stats`, `/var/lib/prometheus2` (if the monitoring piece follows).
   Mirror brys' ZFS properties (recordsize, compression, ARC interaction).
2. **`hosts/oams/llm.nix`** mirroring `hosts/brys/llm.nix` but projecting
   `mkServerModels data "oams" <profile>`; `hosts/oams/default.nix` imports
   `llm.nixos`, `llm.slot`, the `llm` aspect and applies `llm.gpu`.
3. **Registration** in `data/llm.nix`: a `servers.oams` block (routers, swap,
   profiles, `vulkanDeviceSelect = "1002:73df!"`), an `endpoints.oams` entry, and
   `hosts.oams = { set; servedContext; common = {...}; }` on each model oams
   serves.
4. **The toggle** — three layers:
   - a `kdnctl`-style CLI (`oams-llm on|off|status`) that stops the llama-swap
     unit and masks it, so no model can be spawned;
   - an automatic hook on **AC unplug / battery** (a udev or upower-triggered
     oneshot);
   - integration with the existing **gaming scope** detection so a Steam session
     forces LLM serving off, the same signal the build-farm toggle uses.
5. Only *small* GPU models go here (the ones that fit 12 GB). Candidate set is in
   [models-for-oams](models-for-oams/definition.md).

## Open questions

- Does the desktop session need to be disabled to free RAM, or is the model
  small enough that it co-exists? (For the ~4-8 GB small models, co-existence is
  fine; for the 35B MoE it is not.)
- Should oams serve at all when on battery, or only on AC? (Default: AC only.)
- Which models exactly? See the sub-task.

## Sub-tasks

- [models-for-oams](models-for-oams/definition.md) — which models oams serves.

## Incident 2026-11-05: activating oams stranded it, and the fix

While first landing this work a `nixos-rebuild switch` on the live laptop was run.
It failed mid-switch and left the host with **sshd down** and a failed
`sops-install-secrets`. The box was still reachable — this session actually runs
on oams — but every service that depends on `kdn-secrets.target` was dead
(`home-manager-*`, `nix-gc`, `sshd`).

**Root cause:** `hosts/oams/llm.nix` adds the shared `llms.nonsensitive.sops.yaml`
to oams, but that file was not encrypted to any identity oams can use at boot (no
YubiKey present, no TPM age identity enrolled). `sops-install-secrets` failed with
`0 successful groups required, got 0`, which failed `kdn-secrets.target`, which
failed sshd's dependency. This is the same failure class as the brys incident of
2026-11-04 recorded in [docs/local-llms.md](../../../local-llms.md).

**Fix applied:** oams's SSH host key, derived to age via `ssh-to-age` (already the
unattended mechanism the secrets aspect uses), is now a recipient in the `llms`
rule. `sops updatekeys` was run; oams decrypts the file with no YubiKey and no
prompt (verified on the host).

**Lessons for the rest of this task:**

1. **Never `switch` a laptop's SSH-critical config blind.** Use
   `nixos-rebuild boot` (or build + `switch-to-configuration boot`) and reboot
   deliberately. The running generation is not worth risking for a config comment.
2. **Any new host that gains a sops file must first be verified to decrypt it
   unattended**, before the file is wired in. The rule: add the recipient, run
   `sops updatekeys`, then prove `SOPS_AGE_KEY_CMD=... sops -d` on the target with
   no touch. Otherwise the next boot has no SSH.
3. `sops-install-secrets` must be `wanted`/`after`, not `required`, by sshd — see
   the brys fix; oams inherited the safe ordering but still lost sshd because the
   whole target failed as a hard dependency at the sshd unit.
4. Pin the last-good and the new generation as GC roots under
   `/nix/var/nix/gcroots/kdn-pinned/` before/after any risky activation. Gen 730
   (last good), 731 (the failed switch), 732 (the fixed `boot`) are pinned.

**Deployment state at end of this run:** generation 730 is running (last good,
pinned); generation 732 carries the oams llama-swap work and the sops fix and is
installed as the next boot, not yet activated. A reboot of oams applies it.

## Progress 2026-11-05

- **Datasets**: `/var/lib/kdn/llms/{models,sessions}` and `/var/lib/llm-stats`
  declared in `hosts/oams/disko.nix`; modes fixed by `systemd.tmpfiles`.
- **Host wiring**: `hosts/oams/llm.nix` projects `servers.oams`; GPU pinned to the
  6800M (`1002:73df`). llama-swap enabled via the `llm` aspect.
- **Serving toggle**: `oams-llm on|off|auto|status` + 30 s timer. `auto` serves
  only on AC and with no `app-steam_app_*` scope; off auto-tripped stops and
  masks llama-swap. Reuses the build-farm gaming signal.
- **Models served**: the 4 small fast models (gemma-4-e4b, granite-4.2-3b,
  qwen3.5-0.8b, qwen3.5-2b) plus the measured winner **qwen3.5-35b-a3b** at
  `-ngl 99 -n-cpu-moe 24` (113 pp / 10.2 tg, stable).
- **Deployed as boot generations** 733 and 734 (pinned as GC roots). NOT switched
  live; a reboot of oams applies it. See the incident note above for why.

### Still open

- The serving toggle has not been exercised end-to-end (no reboot yet).
- GPU stability: the dense 9B fully on the 12 GB card faults the GPU; only the
  MoE-with-n-cpu-moe path is proven stable. Watch for this if more models are added.

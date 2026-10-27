---
type: Task
description: Convert host `gaz` (Lenovo C13 Yoga Chromebook) from a Crostini VM into a real den-based NixOS workstation, and run the whole job as a supervised local-LLM agent fleet so the fleet itself gets evaluated.
status: open
authored_by: agent
timestamp: 2026-10-27T19:15:00+01:00
---

# `gaz`: a real NixOS workstation, built by a supervised local-LLM fleet

This is an **umbrella task**. It has three open sub-tasks:

| Sub-task | What it delivers |
|---|---|
| [001-nanokvm-operations](001-nanokvm-operations/definition.md) | A skill plus a doc for the NanoKVM operations an agent needs: screenshot, keys, power, HID health. |
| [002-gaz-to-den-hosts](002-gaz-to-den-hosts/definition.md) | `gaz` moved to `hosts-den/`, workstation profile, ZFS-on-LUKS impermanence, MrChromebox boot. |
| [003-fleet-evaluation](003-fleet-evaluation/definition.md) | The measured answer to "how do we drive work with the local fleet most efficiently". |

Read [research.md](research.md) for the verified facts this plan rests on, and
[design.md](design.md) for the harness that runs the job.

## Why

Two goals share one run, on purpose. Each makes the other cheaper.

1. **The machine.** `gaz` is the only Chromebook in the fleet, and it is the only
   host that still runs as a Crostini container (`hosts/gaz/default.nix`). It has
   16 GB of RAM and, reportedly, a 2 TB disk. That is enough to be a real
   workstation. Today it is a VM with a 20 GB disk image, no disk layout, and no
   den aspects. It should be a first-class den host, built like `brys`: one
   declarative disk layout, ZFS-backed impermanence, the workstation profile.
2. **The fleet.** We run a large local model fleet on `brys`, but we have no
   measured answer to "which model for which job, and what can run at the same
   time". A long, messy, real task — firmware flashing a laptop through a KVM —
   is the honest test. It has screenshots, shell work, code edits, hardware
   dead ends, and failure modes that a benchmark does not produce.

A local orchestrator is slow. That is the point: we want to know whether a slow
capable model plus fast small ones beats a fast model alone, and where it breaks.

## The persons in the run

Four roles. Only one of them is a human, and it is the one with hands.

### 1. The owner (human)

- Owns the machine and the physical world.
- Presses and holds the power button when the orchestrator asks.
- Attaches the USB installer when asked, and confirms that the disk they
  expected is the disk present.
- Approves anything irreversible.
- Reviews commits and pushes. The fleet never pushes.
- **Is told what is happening, in plain words, at every hand-off.** The
  orchestrator must ask in one short message and then wait.

### 2. The overseer (SaaS model, one session)

- Runs the harness: starts the Zellij session, spawns the orchestrator, watches.
- Does **not** do the technical work. It supervises it.
- Watches for: OOM kills, evicted models, a dead HID path on the KVM, a looping
  or idle orchestrator, a stalled sub-agent, a build that never ends.
- Feeds the orchestrator short corrections and the missing fact that unsticks it.
- Acts as the **oracle**. The orchestrator may ask it a hard question; the
  overseer answers with a stronger model than any local one.
- Records the evaluation data: turn times, which alias did what, what failed.
- Escalates to the owner when the physical world is needed, or when the run
  should stop.

### 3. The orchestrator (one opencode session, local model)

- The work driver. One session, one Zellij pane, one owner of the plan.
- Model: Qwen3.8-Flash-Next at **high** thinking (`qwen-high`, the alias
  `orchestrate-deep-slow`). Capable, slow, 1M context, accepts images.
- Decides, delegates, writes the plan, keeps the board, commits with `jj`.
- **Delegates almost everything.** Its own turns should be short: read the
  result, decide, delegate again.
- May call the overseer when it is stuck, and must do so early rather than
  spin.
- Must never start a long unsupervised loop; see the loop rules in
  [design.md](design.md).

### 4. The fleet (many opencode sub-agents, local models)

- Named by purpose alias (`chat-dumb-fast`, `code-std-fast`, `vision-quick-fast`,
  ...). See [design.md](design.md) for the ladder.
- Start at the fastest tier. Escalate only when the fast tier fails twice, or
  when the task is clearly `std` or `deep`.
- One narrow task each, with the exact output shape. No open-ended goals.
- Cheap to throw away. A wrong answer from a 4B is cheaper than a slow answer
  from a 27B.

## Requirements

### Hard requirements

1. `gaz` runs NixOS **directly on the hardware**, not in Crostini. UEFI boot
   from the internal disk. No dependence on ChromeOS.
2. `gaz` is defined in `hosts-den/`, not `hosts/`, and holds a
   `den.hosts.x86_64-linux.gaz` entry with aspects, like `hosts-den/orr`.
3. The disk layout uses the repo's own convention: `kdn.disks` (impermanence,
   tmpfs root, ZFS pool on LUKS with a detached header) plus `fs-zfs`. Not a
   hand-written `fileSystems` block.
4. The machine profile is the workstation bundle, as close to `brys` as the
   hardware allows: `kdn.profile.machine.workstation` and its aspects.
5. The run is driven end to end by the local fleet, with the overseer as the
   only SaaS model in the loop.
6. Every step that needs hands is a **blocking question to the owner**, and it
   is logged.
7. The fleet never pushes to a remote. Every change lands as a local `jj`
   commit for the owner to review.
8. No secret reaches the repo, a log, or a screenshot. The NanoKVM API key and
   any password stay in a shell variable.

### Soft requirements

- Prefer an existing aspect over a new option. A `gaz`-only block should be
  small; anything generic belongs in `modules/den/aspects/`.
- Keep the old `hosts/gaz` file until the den host boots. Then delete it in its
  own commit.
- Record numbers, not impressions. If a claim is not measured, it says so.

## Phases

Each phase ends with a commit and a one-line entry in `.worklog.md`.

| Phase | Work | Gate |
|---|---|---|
| 0 | Harness up: KVM operations known, Zellij session, orchestrator spawned, watch loop running. | A test delegation to a fast alias returns. |
| 1 | Recon: read the current `gaz` config, the disk aspect, `brys`, and the Crostini module. Write the migration plan. | Plan committed. |
| 2 | `hosts-den/gaz` skeleton: class, aspects, hostId, tmpfs root, GRUB off. It evaluates. | `nix eval .#denConfigurations.gaz` returns a system. |
| 3 | Hardware: model, keyboard, panel, `nixos-hardware` entry, firmware. Owner confirms the 2 TB disk. | `lsblk` and `dmidecode` captured from the live machine. |
| 4 | Disk: `kdn.disks` layout for the real devices, plus the ESP. | The installer media boots and finds the layout. |
| 5 | Install and first boot, over the KVM. | `gaz` boots to a login, and SSH answers. |
| 6 | Workstation profile parity, then the old `hosts/gaz` removal. | `nixos-rebuild switch` on the machine. |
| 7 | Evaluation write-up. | [003-fleet-evaluation](003-fleet-evaluation/definition.md) is done. |

## Human-in-the-loop hand-offs (expected)

The owner is needed at these points. The orchestrator must pause and ask, and
must say which one it is.

1. **Power on.** The NanoKVM currently reports no HDMI signal, so the device is
   off or asleep. Press and hold power, then release.
2. **Developer-mode / firmware menu.** MrChromebox install needs the ChromeOS
   recovery or developer flow: `Esc+Refresh+Power`, then `Ctrl+D`, and one
   reboot. This is physical.
3. **Firmware write-protect.** Recent Chromebooks need the battery disconnected
   or a jumper for the firmware write. Ask before opening anything.
4. **USB media.** Insert the NixOS installer stick, and confirm the boot order.
5. **Disk confirmation.** The owner states what the disk should be; the agent
   proves what it is.
6. **Any erase.** One explicit yes, once, per disk.

## Acceptance

- `gaz` boots NixOS from its internal disk with no ChromeOS.
- `hosts-den/gaz/default.nix` holds the definition; `hosts/gaz/` is gone.
- The disk layout is `kdn.disks` with ZFS impermanence, and `/` is tmpfs.
- The workstation profile is on, with the desktop the hardware can carry.
- A reboot leaves the machine clean and the persistent paths restored.
- The evaluation has measured numbers for at least: turn latency per tier,
  which alias failed which job, the concurrency actually achieved, and the
  points where the run needed the owner or the overseer.

## Risks

| Risk | Mitigation |
|---|---|
| No HDMI signal from the KVM (seen today) | Phase 0 gate: prove a screenshot works before any planning. If it fails, the owner powers the machine on. |
| MrChromebox does not support this exact model | Check the supported list first, in phase 3, before any flash. Fall back to running from USB or keeping Crostini. |
| A 2 TB disk may not exist (eMMC is common on this model) | Verify with `lsblk`/`smartctl` before writing a layout. Adapt the layout to the real device. |
| The KVM HID path dies mid-run (documented for `anji`) | Probe `HIDIdleTime` after every pause; report early; prefer a fresh session over a rebind loop. |
| The orchestrator loops and burns hours | Watch loop with a step limit and an idle timer; the overseer interrupts. |
| A frontier model swap stalls for minutes | The watch loop reads `/running` and the swap log, and tells the orchestrator to wait rather than retry. |
| ZFS needs a unique 8-char `hostId` | Generate one from the machine UUID and record it. |
| Secrets leak through a screenshot | Screenshots stay in `/tmp/opencode/`, are never committed, and are described only in plain words. |

## Open questions

- Which exact C13 Yoga model is it, and does MrChromebox list it as UEFI-
  supported? Unknown until phase 3.
- Where is the 2 TB disk? The model commonly ships eMMC. If it is eMMC, the
  layout must not assume NVMe wear behaviour.
- Does the Chromebook keyboard and audio work under mainline? `nixos-hardware`
  has Chromebook entries; check which one fits.
- Does the panel need a `kanshi`/`edid` entry, as `brys` does?
- Should `gaz` keep the Crostini host entry as a fallback boot option, or drop
  it entirely in the same change?

## Neighbouring work

- [../tpm-age-sops-keys/definition.md](../tpm-age-sops-keys/definition.md) — the
  sops decryption chain. A new host needs its own SOPS recipients and its own
  unattended decrypt path.
- [../hardware-inventory/hardware.research.md](../hardware-inventory/hardware.research.md) — the fleet
  inventory, which lists `gaz` today as "no inference use".
- [../nanokvm-mcp-macos-control/definition.md](../nanokvm-mcp-macos-control/definition.md) — the verified
  KVM recipe for `anji`. It is the base of sub-task 001.
- [../zellij-llm-opencode/done.md](../zellij-llm-opencode/done.md) — the tool that drives the session.

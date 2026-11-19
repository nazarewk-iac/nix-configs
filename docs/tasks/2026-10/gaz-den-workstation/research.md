---
type: Research
description: Verified local facts for the gaz conversion: the current host definition, the den host loader, the disk and workstation aspects, the NanoKVM at kvm-fa56, the brys model fleet's real concurrency, and the session tooling.
task: definition.md
authored_by: agent
timestamp: 2026-10-27T19:20:00+01:00
---

# Research: what is true today

Everything below was read from this repository or measured on a live host on
2026-10-27. Where a fact is unverified it says so.

## 1. The current `gaz`

`hosts/gaz/default.nix` is a **Crostini VM**, built by the
`nixos-crostini.nixosModules.baguette` module:

| Fact             | Value                                                                  |
| ---------------- | ---------------------------------------------------------------------- |
| Class and system | `nixos`, `x86_64-linux` (`hosts/gaz/meta.json`)                        |
| Boot module      | `kdnConfig.inputs.nixos-crostini.nixosModules.baguette`                |
| Disk             | `virtualisation.diskImageSize = 20 * 1024` — a 20 GB image, no `disko` |
| RAM              | `virtualisation.buildMemorySize = 16 * 1024`                           |
| Profile          | `kdn.profile.machine.baseline`, desktop off, all LLM CLIs off          |
| Secrets          | **no SSH host keys** (`# TODO: add SSH host keys (using kdnctl?)`)     |
| Network          | firewall trusted on `nb-priv` and `eth0`                               |

So this host has no disk layout, no workstation profile, no aspects, and no
graphical session. It is a container that runs a baseline NixOS.

The host is not in `hosts-den/` at all. `hosts-den/` holds one host: `orr`.

## 2. The den host loader

`modules/den/flake-module.nix` reads `hosts-den/` with `builtins.readDir` and
imports every directory. A new host is one directory, with no wiring edit.

| Rule                                                                                                                                        | Source                |
| ------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| Path is `hosts-den/<name>/default.nix`.                                                                                                     | `hosts-den/README.md` |
| There is **no** `meta.json`; the file states its own system and class.                                                                      | same                  |
| The output is `denConfigurations.<name>`, and the host is also merged into `nixosConfigurations.<name>`.                                    | `hosts-den/README.md` |
| `flake.hosts` must stay old-tree-only: two k8s modules do a by-name lookup there for `kdn.networking.*`, which a den host does not declare. | same                  |
| Compare **option values**, never `drvPath`; the baseline profile copies the whole repo into the store.                                      | same                  |

The one existing host, `hosts-den/orr/default.nix`, is a skeleton:

```nix
{ kdn, ... }:
{
  den.hosts.aarch64-linux.orr.class = "nixos";
  den.aspects.orr.includes = [ kdn.hw-usbip kdn.hw-yubikey kdn.locale kdn.nix-config ... ];
  den.aspects.orr.nixos = {
    networking.hostName = "orr";
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
    boot.loader.grub.enable = false;
    system.stateVersion = "26.05";
  };
}
```

`gaz` is the same class and system (`x86_64-linux`), so it is the closest
working example.

## 3. The disk convention (`kdn.disks`)

`modules/den/aspects/disks.nix` is the den port of `modules/universal/disks/`.
It implements impermanence on ZFS on LUKS:

- root is **tmpfs**; every boot is clean;
- a ZFS pool on a LUKS volume with a **detached header** holds what persists;
- `preservation` bind-mounts each kept path back;
- the whole disko layout is generated from a short device description.

`brys` uses it like this (`hosts/brys/default.nix`):

```nix
kdn.disks.enable = true;
kdn.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_...-0:0";
kdn.disks.luks.volumes."vp4300-brys" = {
  targetSpec.path = "/dev/disk/by-id/nvme-...";
  uuid = "cbfe2928-2249-47fa-a48f-7c53c53a05d4";
  headerSpec.partNum = 2;
};
```

Two rules that bite:

1. **Never include both** `disks` and `fs-luks-zfs`; both write `disko.devices`
   and the initrd order, and an assertion refuses the pair.
2. ZFS needs a **unique 8-char `networking.hostId`**. `brys` has `0a989258`, and
   the comment says how it was made: `cut -c-8 /proc/sys/kernel/random/uuid`.

`fs-zfs` must be included beside `disks`; the port removed the forward write.

## 4. The workstation convention

`modules/den/aspects/profile-workstation.nix` is the top bundle: it reaches
`profile-desktop` and `profile-dev`, adds sway, remote desktop, the media
editors and two virtualisation aspects, and carries the clevis initrd unlock.

`brys` composes it as a **host block**, not as one aspect
(`hosts/brys/default.nix`):

```nix
kdn.profile.machine.workstation.enable = true;
kdn.hw.gpu.amd.enable = true;
kdn.hw.cpu.amd.enable = true;
zramSwap.enable = lib.mkDefault true;
zramSwap.memoryPercent = 50;
boot.tmp.tmpfsSize = "32G";
```

The closest hardware precedent for a laptop is
`modules/den/aspects/hw-dell-e5470.nix`: it loads the needed kernel modules,
sets zram, and includes the GPU and modem aspects. A Chromebook needs the same
kind of file, plus `nixos-hardware` (the input is already pinned in
`flake.nix`).

## 5. The NanoKVM on `gaz`

| Fact                        | Value                                                                                                              | How verified                                |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------- |
| Address                     | `kvm-fa56.lan.etra.net.int.kdn.im` = `192.168.73.122`                                                              | `getent hosts`                              |
| Registered in the config    | yes, MAC `48:da:35:6f:fa:56` → name `kvm-fa56`                                                                     | `hosts/etra/default.nix:215`                |
| Firmware version            | `2.5.2`                                                                                                            | `cat /kvmapp/version` over SSH              |
| SSH                         | `ssh root@kvm-fa56...` works                                                                                       | verified                                    |
| MCP endpoint                | `POST https://kvm-fa56.../api/mcp`, Streamable HTTP, self-signed TLS (`-k`)                                        | `401` without the key, `tools/list` with it |
| Key                         | `/etc/kvm/mcp.json`, field `apiKey`, mode `0600`                                                                   | read over SSH, never recorded               |
| Tools                       | `cube_screenshot`, `cube_move_mouse`, `cube_click_mouse`, `cube_press_keys`, `cube_type_text`, `cube_scroll_mouse` | `tools/list`                                |
| **Video capture right now** | **unavailable**. `cube_screenshot` returns `screenshot capture is temporarily unavailable` at any `timeoutMs`.     | 3 attempts                                  |
| Device load                 | load average ≈ 5.5 on a 128 MB box                                                                                 | `uptime`                                    |

The capture failure has a likely cause. `dmesg` shows repeated `LT6911--:-- INT!!##`
— the LT6911 is the HDMI-to-CSI bridge, and that line is the no-signal path.
`ls /dev/video*` is empty by design: NanoKVM captures through the vendor
`soph_vc_driver`/`soph_vi` pipeline, not V4L2. So the device's software is
alive and the **source has no picture**: the Chromebook is off, or its lid is
closed with no external output.

**This makes "press the power button" the very first hand-off of the run**, not a
late one.

The full MCP call shape is in
[../../nanokvm-mcp-macos-control/definition.md](../../nanokvm-mcp-macos-control/definition.md).
That document also carries the hard-won operating rules, which apply here:
poll the frame until it matches the expected state before each next action,
`sleep 2` after every injection, probe `HIDIdleTime` after a pause, and never
click anything destructive.

## 6. The model fleet: real concurrency, not a list of names

The alias list is in the `kdn-llms` skill and in `hosts/brys/llm-routers.nix`.
What the skill does not state, and what decides the fleet design, is the
**process and device layout**. Read from the generated config on `brys`
(`/nix/store/vhssi9i…-config.yaml`):

- One `llama-server` process per model. `llama-swap` starts it on the first
  request and keeps it warm (`globalTTL = 0`).
- **Only the two frontier models run `--parallel 4` with `--kv-unified`:**
  `deepseek-v4-flash` and `qwen3.8-flash-next`. **Every other model runs
  `--parallel 1`.** One request at a time per model process.
- 15 models run on **Vulkan0**, the 8 GB W6600 GPU: `qwen3.5-0.8b`,
  `qwen3.5-2b`, `qwen3.5-4b`, `tmax-2b`, `tmax-9b`, `granite-4.2-3b`,
  `granite-4.2-8b`, `mimo-v2.6-qwen-9b`, `ministral-3-3b-{instruct,reasoning}`,
  `ministral-3-8b-{instruct,reasoning}`, `olmo-3-7b-instruct`,
  `gemma-4-e2b`, `gemma-4-e4b`. They do **not** contend for CPU memory
  bandwidth, but they share 8 GB of VRAM.
- The CPU models contend for the same ~40 GB/s. The measured penalty from
  [../brys-grunt-colocation/colocation.research.md](../brys-grunt-colocation/colocation.research.md):
  any co-resident CPU model **halves** the frontier, and a co-tenant above
  ~45 GB **evicts** it and costs a 10–20× cold re-read.
- Routing sets in the live config: `main: (deepseek-v4-flash | qwen3.8-flash-next)`
  and `with_grunt: (qwen3.5-4b) & (deepseek-v4-flash | qwen3.8-flash-next)`.
  So the 4B grunt **may** run beside either frontier model, because it is on the
  GPU.
- `qwen3.5-4b` carries four aliases at once: `grunt`, `chat-dumb-fast`,
  `code-quick-fast`, `tiny-quick-fast`. A sub-agent that names any of the four
  hits **the same process**, and therefore the same one-at-a-time queue.
- `swap.debug = true` on `brys` today, so `journalctl -u llama-swap` holds the
  swapper **and** every child `llama-server` log. See
  [../../local-llms.md](../../local-llms.md#watching-the-logs-in-practice).

Consequences for the design:

1. Parallel sub-agents only truly overlap when their aliases map to **different
   processes**, and those processes fit in RAM (CPU) or VRAM (GPU).
2. A fan-out of five `chat-dumb-fast` tasks is **serial**, not parallel. Fan out
   across _distinct_ aliases instead.
3. The frontier at `--parallel 4` can absorb four concurrent requests, so the
   orchestrator itself is rarely the bottleneck; the small tier is.

## 7. Session tooling

`zellij-llm opencode` exists and is tested
([../zellij-llm-opencode/done.md](../zellij-llm-opencode/done.md)):

| Command                                           | Effect                                                                           |
| ------------------------------------------------- | -------------------------------------------------------------------------------- |
| `spawn --pane oc --model <id> [--opencode-arg …]` | starts opencode in a new pane, inside `devenv shell --` when the project has one |
| `send --pane oc --text '…'`                       | types a prompt and presses Enter                                                 |
| `watch --pane oc [--for 30m]`                     | prints `state=RUNNING` / `state=IDLE`; returns on the first RUNNING→IDLE         |
| `list`                                            | pane name and opencode session id                                                |
| `attach`                                          | prints the `zellij attach` command                                               |

`opencode` itself takes `--model provider/model`, `--agent <name>` and `--auto`
on the TUI. `--auto` auto-approves permissions that are not explicitly denied —
**required for an unattended orchestrator**, and dangerous, so the permission
baseline in the harness must still deny pushes.

Thinking depth is **not** a command-line flag on the TUI. The repo sets it per
agent with `options.chat_template_kwargs` (`hosts/oams/devenv.nix`, `mkAgents`).
The tier agents `qwen-high`, `qwen-low`, `ds4-low`, … are `mode = "subagent"`.
So "an orchestrator on Qwen at high thinking" needs either:

- a new **primary** agent (for example `orchestrator`) with
  `model = "brys/qwen3.8-flash-next"` and
  `options.chat_template_kwargs = qwenThinking.high`; or
- the alias `orchestrate-deep-slow` with a per-request override, which is not
  reachable from the TUI today.

Phase 0 of the run must settle this.

Providers on this machine (`oams`): `brys` (discovery, all aliases) and
`requesty` (SaaS). `requesty` is wired by the `oams` devenv profile. The
orchestrator therefore **can** reach a SaaS model as an `opencode run` one-shot,
but it should not need to: the overseer is the oracle.

## 8. What past sessions say

The two earlier attempts at this same job produced almost nothing, and the
reason matters:

- `ses_e81f21854ffedoN4pTTKPBieAt` (2026-10-27 15:50) holds **one** part: the
  prompt. The spawned orchestrator never ran a turn.
- `ses_e81e02567ffeEyVoXEDZejrLrU` (16:09) is the _SSH_ session: it found the
  `pcscd.socket` ordering cycle that stopped `sshd` on `brys`, and wrote the
  `hw-yubikey.nix` fix plus the TPM task. It never touched `gaz`.
- `ses_e81de0d85` is the session that wrote this document.

So there is **no prior `gaz` work to inherit**. There is also no NanoKVM skill
yet: `.agents/skills/` holds `flake-patches`, `flake-update`,
`flake-update-fork`, `jujutsu-vcs`, `kdn-llms` and `zellij` only. The verified
KVM recipe lives in the `nanokvm-mcp-macos-control` task, written for `anji`.

That is why sub-task 001 exists. Without a skill, every future agent re-derives
the MCP call, the key location, and the HID rules.

## 9. Unverified

- The exact C13 Yoga model, and whether MrChromebox (often written
  `mrchromebook`) lists it as UEFI-supported. Its device list is the only
  authority; check it before any firmware work.
- The presence of a 2 TB disk. The model line commonly ships eMMC; this must be
  settled with `lsblk` on the live machine before any layout is written.
- Whether the internal keyboard, touchpad, audio and panel work under mainline.
- Which `nixos-hardware` entry fits (Chromebook support is per-model).
- Whether the W6600 grunt and a CPU frontier model genuinely co-serve at
  acceptable latency under a real agent load. That is an evaluation question,
  and [003-fleet-evaluation](003-fleet-evaluation/definition.md) measures it.

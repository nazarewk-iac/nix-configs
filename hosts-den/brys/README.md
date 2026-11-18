---
type: Reference
description: brys host — Ryzen 5950X / 128 GB DDR4 workstation. Also serves local LLMs via the kdn.llm.local slot.
timestamp: 2026-11-18T14:11:34+01:00
---

# brys host

Ryzen 9 5950X workstation, 128 GB DDR4, AMD Radeon AI PRO R9700 (32 GB, Vulkan compute for the
local LLMs). The RX 550 drives the displays.

- Host config: [`hosts-den/brys/default.nix`](default.nix)
- Build: `nix build .#denConfigurations.brys.config.system.build.toplevel`, copy it to the host, then `nix-env -p /nix/var/nix/profiles/system --set` + `switch-to-configuration switch`
- The universal twin (`hosts/brys/`) was removed on 2026-11-18; this directory is the only brys config

## Power-off recovery

brys has a motherboard or PSU fault: after any power-off (front-panel button, NanoKVM ATX
pulse, or a greeter shutdown), the machine can fail to start again. The power LED stays on, but
there is no POST, no HDMI signal, and the USB devices do not enumerate. A power-on press, a
reset pulse and a WoL magic packet do nothing.

The machine recovers only after it is fully disconnected from AC for 20-60 minutes. USB devices
backfeed enough power to keep the fault latched, so unplug the USB peripherals (including the
NanoKVM USB cable) together with the mains lead.

Observed on 2026-11-18: a greeter-initiated shutdown left brys dark for about 25 minutes; it
returned after the power lead was pulled.

**A warm `reboot` can also land in the fault.** A `reboot` on 2026-11-18 stopped at the same dead
state (no network, no HDMI, `udc` still `configured`). The NanoKVM **reset** pulse recovered it:
`echo out > /sys/class/gpio/gpio505/direction; echo 1 > .../value; sleep 1; echo 0 > .../value`
on `kvm-26e2`. The PSU stays on across a reset, so the AC-disconnect latch does not engage. Try the
reset before asking for a physical power press.

The NanoKVM reports the same fault as a dead KVM: no screenshot frame and `write /dev/hidg0: i/o
timeout`. Before touching the KVM, check `/sys/class/udc/*/state` on the KVM host. `not attached`
means the machine does not enumerate the gadget, which fits a powered-off brys. The KVM's power
LED input reads `1` even when the machine is off, so it proves nothing.

Reference and independent research:
<https://assistant.kagi.com/chat/6a8520e2-c7b2-4bb4-97d2-3c5247e1c25e>

Operational notes:

- Never pulse the NanoKVM power key to "test" a running host. A short ATX press is a clean
  shutdown request.
- The SDDM greeter puts its power control in the top-right corner. Keyboard focus can land
  there, and `Space` activates it. Change the session with the mouse, not with `Shift+Tab`.

## Local LLM serving

brys runs several local LLMs through the standalone `kdn.llm.local` slot
(backend: llama-server router mode, OpenAI-compatible API on `127.0.0.1:39703`).
The grunt and surveyed sets co-reside on the R9700 by tier; the frontier
(Qwen3.8-Flash-Next at 1M context, YaRN x4) retired from the fleet on
2026-11-13 on electricity grounds, so the `main` router is empty.

The `llms` appliance specialisation from the universal tree is **not ported** to the den host
yet. Only the `desktop` boot profile exists, so the served context sizes are the ones that share
RAM with a browser (see `data/llm.nix` `servers.brys.profiles.desktop`).

## WAN shaping

A model download from Hugging Face reaches ~105 MB/s (845 Mbit/s) on this host, which is more
than the 1 Gbit/s WAN carries together with anything else: every other host then sees stalled
handshakes. `wan-shaping.nix` caps **inbound TCP/443** at 600 Mbit/s on `kdn-eth-2g`, with an
`ifb` device and a `tbf` qdisc. A 100 GB quant then lands in about 25 minutes and the other
400 Mbit/s stay free. LAN, SSH, the llama-swap API and uploads are not shaped.

Measured 2026-11-18: a 300 Mbit setting delivered 34.5 MB/s; the shipped 600 Mbit setting
delivers 68-70 MB/s with the qdisc reporting `overlimits`. Service: `kdn-wan-shaping`
(`systemctl disable --now kdn-wan-shaping` turns it off).

Rejected alternatives: `trickle` under-delivers by 3x at these rates; the `drek` border router
(OpenWrt, Cortex-A53) shapes, but its DSA port counters do not report the shaped traffic and a
200 Mbit cake setting delivered 446 Mbit/s, so it cannot be tuned there.

The exact deployed state — models, serving endpoint, download mode and rate
cap, persistence, and secrets — is documented in
[`docs/local-llms.md`](../../docs/local-llms.md). The box hardware and the
measured performance are in [`performance.md`](performance.md).

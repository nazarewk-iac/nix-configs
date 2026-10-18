---
type: Task
description: Research-first plan to distribute self-hosted LLMs across several owned machines (brys, Orion O6, oams, N100 NAS fleet, CWWK 1240P, Pi4s), with a router/scheduler that spans hosts.
status: open
authored_by: agent
timestamp: 2026-10-18T06:00:00+02:00
---

# Multi-machine local LLMs

One machine, `brys`, serves all self-hosted models today. Its work is CPU-bound: the
models run on the CPU, and the two GPUs in the box carry almost none of the weight. The
user owns several other machines. Most are idle or offline. A layout that spreads models
across these machines could give more speed and some redundancy. This task is the
research that must come before any such build.

## Hardware available

The table below comes from the sibling inventory. Do not re-derive it. See
[hardware.research.md](../hardware-inventory/hardware.research.md) for the sources and the
full list.

| Machine | CPU | RAM | GPU | State | Notes |
|---|---|---|---|---|---|
| brys | AMD Ryzen 9 5950X 16C/32T | 128 GB DDR4 | Radeon PRO W6600 8 GB | serving today | the production LLM server, CPU-bound |
| Orion O6 | CIX P1 12-core SoC | 64 GB LPDDR5 | Mali (slower than CPU) | **unconfigured** | free PCIe Gen4 x16 slot; no Nix config; numbers unmeasured |
| oams | AMD Ryzen 9 5900HX class | not documented | Radeon RX 6800M 12 GB | **interactive** | gaming/dev laptop; only real dGPU |
| 3x N100 NAS | Intel N100 | 32 GB DDR4-3200 | iGPU only | **offline** | small MoE grunts possible |
| 1x CWWK mini PC | Intel i5-1240P (12th gen) | **DDR5, 64 GB** | iGPU | **offline** | Proxmox/firewall box |
| 3x RPi4 | BCM2711 Cortex-A72 | 4 GB | VideoCore VI | **offline** | very low fit |
| briv | Raspberry Pi 4 | (Pi4) | VideoCore VI | serving (Home Assistant) | not an inference host |

## Why research first

To spread models across hosts is a real design problem, not a simple move. It asks:
which model runs on which host, how one OpenAI endpoint routes across the hosts, how a
model stays hot, what happens when one host goes down, and how network bandwidth trades
against VRAM and RAM. A wrong layout wastes the hardware or breaks the endpoint. Do the
research now, ahead of time. Build later.

## Sub-questions to research

- (a) One logical OpenAI endpoint across N hosts. Compare a router or scheduler that spans
  hosts: `llama-swap` `peers`, LiteLLM, or a custom proxy.
- (b) Model placement policy. Rank the fit of a host by VRAM first, then RAM, then
  bandwidth.
- (c) The Orion O6. Decide if it should run with a discrete GPU in its free PCIe x16 slot,
  or with its own SoC only.
- (d) The N100 fleet. Decide if these boxes can host small MoE grunts.
- (e) Failure and redundancy. Keep a conversation on the host that holds its KV. Define the
  fallback when that host goes down.
- (f) Network topology. The hosts reach each other over the existing VLANs or over netbird.
  Measure what that path costs for a large prefill.
- (g) Hot config reload across hosts. Read
  [../brys-grunt-colocation/](../brys-grunt-colocation/) for the current single-host
  approach.

## Constraints

- `oams` is an interactive machine (gaming, media, dev). Use it for small models only, and
  only when it is free.
- Several boxes are offline and have no Nix config (the Orion O6 has none). Do not assume
  that they can be touched yet.
- Do not change hardware that the user has not released for this work.

## Acceptance criteria

The deliverable is research, not an implementation. This task is done when it produces:

1. A placement table: one row per model, the host it should run on, and why.
2. A routing design: how one OpenAI endpoint reaches every chosen host.
3. A go/no-go per host: which machines join the layout now, and which wait.

No code and no host change belong to this task.

## References

- [hardware.research.md](../hardware-inventory/hardware.research.md) — the hardware
  inventory and the inference-candidate ranking.
- [docs/local-llms.md](../../../local-llms.md) — the current local-LLM setup.
- [hosts/brys/](../../../../hosts/brys/) — the production LLM server config, including
  `performance.md` and the `llm-*.nix` model files.
- [../brys-grunt-colocation/](../brys-grunt-colocation/) — the single-host grunt
  colocation task, with its router/scheduler research.

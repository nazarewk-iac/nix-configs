---
type: Research
description: Verified hardware inventory across all repo hosts plus owned-not-configured boxes, with an inference-candidate ranking.
task: definition.md
authored_by: agent
timestamp: 2026-10-18T06:00:00+02:00
---

# Hardware inventory

HARDWARE INVENTORY (verified from repo `hosts/*/meta.json`, `docs/`, and opencode sessions on 2026-10-18):

| Machine | Arch | CPU | RAM | GPU | Storage | Role | Inference fit | Source |
|---|---|---|---|---|---|---|---|---|
| brys | x86_64-linux | AMD Ryzen 9 5950X 16C/32T | 128 GB DDR4 (125 GiB usable) | Radeon PRO W6600 8 GB (1002:73e3) + Radeon 540/550 "Lexa" 4 GB (both ~useless for weights) | 2x 2 TB NVMe LUKS2 ZFS mirror | NixOS workstation, the production LLM server | high (CPU-heavy, ~40 GB/s) | `hosts/brys/performance.md` |
| Orion O6 (owned, NOT in `hosts/`) | aarch64 | CIX P1 12-core SoC | 64 GB LPDDR5 | Mali (slower than CPU), NPU unusable (SDK not ready), free PCIe Gen4 x16 slot | not documented | standalone Radxa SBC, no Nix config | medium-high: Qwen3-30B-A3B ~14-21 tok/s TG (research claim, unmeasured) | session `ses_f8f0cddafffe2O2P3Q4jv5lZX4` |
| anji | aarch64-darwin | Apple M2 8-core | 16 GB | Apple GPU (Metal) | 256 GB internal + external APFS volumes, Nix Store Ext at `/nix` | macOS Mac mini M2, dual-arch builder | low | `hosts/anji/bootstrap.md` |
| oams | x86_64-linux | AMD Ryzen 9 5900HX class (ROG G513QY) | not documented | AMD Radeon RX 6800M 12 GB class + iGPU | NVMe LUKS ZFS | NixOS gaming/dev laptop | medium (only real dGPU) | `hosts/oams/default.nix:325-326` |
| 3x N100 mini-PC "nas" boxes | x86_64-linux | Intel N100 | 32 GB DDR4-3200 | iGPU only | (user-stated) | offline | low-medium (RAM for small MoE) | user |
| 1x CWWK mini PC (U300E / i5-1240P, 2x10G SFP, 8x2.5G, 2xSATA) | x86_64-linux | Intel 12th gen | 32 or 64 GB | iGPU | (user-stated) | offline, Proxmox/firewall | low-medium | user |
| 3x Raspberry Pi 4 4GB | aarch64-linux | BCM2711 Cortex-A72 | 4 GB | VideoCore VI | microSD | offline | low | `hosts/briv/meta.json`; user |
| briv | aarch64-linux | Raspberry Pi 4 | (Pi4) | VideoCore VI | 256 GB SSD + microSD | NixOS headless, Home Assistant | low | `hosts/briv/default.nix` |
| etra | x86_64-linux | Intel | 32 GB | none | 980 PRO NVMe | NixOS router | low-medium | `hosts/etra/default.nix` |
| moss | x86_64-linux | Hetzner cloud | small | none | cloud | remote | low | `hosts/moss/default.nix` |
| obler, pryll | x86_64-linux | Intel | n/a | Intel iGPU | LUKS ZFS | NixOS desktops | low | `hosts/*/default.nix` |
| pwet, turo, yost | x86_64-linux | Intel (model undocumented) | undocumented | none documented | 250 GB + 1 TB NVMe | NixOS k8s nodes | same as etra | `hosts/*/default.nix` |
| gaz (ChromeOS container), orr (Apple VM), install-iso, kdn-rpi4-bootstrap | | | | | | no inference use | | |

## Inference candidates ranking

1. **brys** — quality frontier on CPU.
2. **Orion O6** — MoE sweet spot, unconfigured.
3. **oams** — fast small models on 12 GB VRAM.
4. **N100 fleet** — small MoE workers.

> ⚠️ The Orion O6 numbers are **unmeasured research claims**. Treat the ~14-21 tok/s TG figure as
> a hypothesis to verify, not a measured result.

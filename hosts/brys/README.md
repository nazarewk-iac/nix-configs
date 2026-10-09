---
type: Reference
description: brys host — Ryzen 5950X / 128 GB DDR4 workstation. Also serves local LLMs via the kdn.llm.local slot.
timestamp: 2026-08-30T00:00:00+02:00
---

# brys host

Ryzen 9 5950X workstation, 128 GB DDR4, AMD Radeon Pro W6600 (8 GB, not
useful for LLMs). CPU-only local LLM serving.

- Host config: [`hosts/brys/default.nix`](default.nix)
- Build: `~/dev/github.com/nazarewk-iac/nix-configs/nixos-rebuild.sh build`

## Local LLM serving

brys runs several local LLMs through the standalone `kdn.llm.local` slot
(backend: llama-server router mode, OpenAI-compatible API on `127.0.0.1:39703`,
DSpark speculative decoding on DeepSeek V4 Flash). The DeepSeek frontier runs
four slots over one unified 320K KV pool; the small-model set is spun out to its
own boot entry so it never competes with DS4 for RAM. Qwen3.8-Flash-Next runs at
1M context (YaRN x4) with the MTP draft head on the CPU and a 37 GiB prompt
cache (`perf.cacheRam`, set to stop the constant evictions of ~5.7 GiB entries).

Four boot-selected appliance specialisations exist (normally selected from the
bootloader; `nixos-rebuild switch --specialisation <name>` also activates one in
place):

- `llm-ds4` (`llm-ds4.nix`) — DeepSeek V4 Flash alone, whole box.
- `llm-small` (`llm-small.nix`) — the small-model router alone, no DS4.
- `llm-qwen` (`llm-qwen.nix`) — Qwen3.8-Flash-Next alone, whole box.
- `llms-frontier` (`llms-frontier.nix`) — DS4 and Qwen in one router with
  `--models-max 1`, so a request swaps the resident model without a reboot.

All four share `llm-appliance.nix` and `llm.nix`.

The exact deployed state — models, serving endpoint, download mode and rate
cap, persistence, and secrets — is documented in
[`docs/local-llms.md`](../../docs/local-llms.md). The box hardware and the
measured performance are in [`performance.md`](performance.md).

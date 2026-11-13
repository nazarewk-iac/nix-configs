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
(backend: llama-server router mode, OpenAI-compatible API on `127.0.0.1:39703`).
The grunt and surveyed sets co-reside on the W6600 by tier; the frontier
(Qwen3.8-Flash-Next at 1M context, YaRN x4) retired from the fleet on
2026-11-13 on electricity grounds, so the `main` router is empty.

One boot-selected appliance specialisation exists (normally selected from the
bootloader; `nixos-rebuild switch --specialisation <name>` also activates one in
place):

- `llms` (`llms-frontier.nix`) — the whole fleet on one llama-swap process,
  plus the isolcpus/ARC kernel tuning the desktop profile does not apply.

It shares `llm-appliance.nix` and `llm-config.nix` with the main profile.

The exact deployed state — models, serving endpoint, download mode and rate
cap, persistence, and secrets — is documented in
[`docs/local-llms.md`](../../docs/local-llms.md). The box hardware and the
measured performance are in [`performance.md`](performance.md).

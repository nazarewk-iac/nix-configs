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
DSpark speculative decoding on DeepSeek V4 Flash).

The exact deployed state — models, serving endpoint, download mode and rate
cap, persistence, and secrets — is documented in
[`docs/local-llms.md`](../../docs/local-llms.md).

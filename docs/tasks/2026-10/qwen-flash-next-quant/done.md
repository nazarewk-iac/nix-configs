---
type: Solution
description: Stood up Qwen3.8-Flash-Next as a third brys boot specialisation with UD-IQ4_XS, measured it, and recorded the tuning.
task: definition.md
authored_by: agent
timestamp: 2026-10-06T20:45:00+02:00
---

# Solution — Qwen3.8-Flash-Next on brys

Task: [definition.md](definition.md).

## Root cause analysis

The task was open because the quant, the runtime support, and the tuning were all
unverified. The Kagi thread was old and theoretical. Three questions blocked the
work: does build 10809 load `qwen4exp`, which quant fits the 128 GB box under the
8 GiB ARC cap, and does the sparse MoE beat DeepSeek V4 Flash.

The verification answers those questions:

- Build 10809 carries `llama_model_qwen4exp`, so the model loads.
- The hybrid GDN+QSA attention makes KV tiny, so `UD-IQ4_XS` fits with room.
- Prefill was the weak point. `ubatch`/`batch` 4096 fixes it.

## Solution

The result is a third boot specialisation, `llm-qwen`, beside `llm-ds4` and
`llm-small`.

1. **`hosts/brys/llm.nix`** gained two arguments, `withQwen` (default false) and
   `qwenContextSize` (default 131072), plus the `qwenPerf` perf block and the
   `qwenModels` model block.
2. **`hosts/brys/llm-qwen.nix`** (new) wires the shared config with
   `withFrontier = false; withSmall = false; withQwen = true;
   qwenContextSize = 131072`, and reuses the shared appliance body in
   `hosts/brys/llm-appliance.nix`.
3. **`hosts/brys/default.nix`** registers `specialisation.llm-qwen`.
4. **Quant:** `unsloth/Qwen3.8-Flash-Next-GGUF`, `UD-IQ4_XS`, 3 shards, 93.7 GB
   total. IQ4_XS keeps the 51B n-gram table inside the weight shards, so the
   whole tree stays resident. KV is small for this hybrid model, so IQ4_XS fits
   under the 8 GiB ARC cap with room; `UD-Q4_K_XL` is ~10 GB bigger and tight.
5. **Config** (`qwenPerf`): ctx-size 131072, batch-size 4096, ubatch-size 4096,
   parallel 1, threads 16, flash-attn on, mmap on, reasoning off, KV type F16
   (the build default). Aliases `qwen` and `frontier`.
6. **Docs:** `docs/local-llms.md` records the specialisation, the model row, the
   architecture and quant facts, and two benchmark rows.

Deployed toplevel:
`/nix/store/zbjfj2czkk38jsplc65i3cirhq418zmq-nixos-system-brys-llm-qwen-26.11.20260908.d6524aa`,
boot entry generation 655.

## Verification steps

Cold-booted brys into `llm-qwen`, waited for the model to warm, then measured:

- `nix eval --json '.#nixosConfigurations.brys.config.specialisation.llm-qwen.configuration.slots.kdn.llm.local.models' --apply builtins.attrNames`
  lists `qwen3.8-flash-next`.
- Model load: ~90 s cold.
- Prefill: 20.1 tok/s at ubatch 1024 (964 tokens / 47.9 s). At ubatch 4096,
  **39.9 tok/s** (run 1: 3425 tok / 85.7 s = 39.95; run 2: 3430 tok / 85.9 s =
  39.91). The ubatch change gives a ~2x gain, the same lever as on DeepSeek.
- Decode: 300 tokens at 4.75 tok/s (predicted_ms 62985). Earlier short samples
  read 3.3-5.5 tok/s (36 tokens).
- Warm prefix-cache repeat: ~1-6.6 s wall.
- Residency: `VmRSS` ~86 GB (`RssFile` ~58 GB, `RssAnon` ~28 GB), `VmSwap` 0,
  `free -g` available ~87 GB, **0 idle major faults/s**, no OOM in the kernel
  log.
- Server: `n_slots = 1`, `n_ctx_slot = 131072`, `kv_unified = 'false'`, a
  16-thread pool.

DeepSeek V4 Flash reference: prefill 15.2-16.5 tok/s, decode ~5-8.6 tok/s. Qwen
prefill is ~2.4x DeepSeek; Qwen decode is slightly lower.

Acceptance criteria:

- Boots and serves the model over the LAN endpoint: **pass**.
- Stays resident, idle major faults ~0, no OOM, healthy `MemAvailable`: **pass**.
- Prefill and decode recorded against the `llm-ds4` baseline: **pass**.
- Short concurrency check if `parallel > 1`: **not run** — `parallel` is 1.
- Measured rows and the chosen quant written into `docs/local-llms.md`: **pass**.
- A `done.md` once verified: **this file**.

## Follow-up notes

- **MTP is blocked.** Build 10809 has no `qwen4exp` MTP graph (no `graph_mtp`
  symbol), so the Unsloth MTP draft heads do not work. The Unsloth README states
  that stock mainline needs PR #28243 or their fork.
- **Speculation is not wired.** `--spec-type` / n-gram speculation is untested;
  the 5950X user in the Kagi thread used `--spec-type ngram-mod`.
- **Only 128K context is tested.** The Kagi thread gives a 128K-200K range. 200K
  is unverified.
- **Frontier question is open.** Decide whether Qwen replaces DeepSeek V4 Flash
  as the frontier model, or stays a separate entry.
- **Optional oams client tier.** The `llm-qwen` model has no client-side context
  tier yet (compare the DeepSeek tiers in `hosts/oams/devenv.nix`).

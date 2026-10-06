---
type: Task
description: Stand up Qwen3.8-Flash-Next in its best-fit quant as a new brys boot specialisation, then benchmark and tune it in practice.
status: open
authored_by: agent
timestamp: 2026-10-06T16:58:30+02:00
---

# Qwen3.8-Flash-Next as a brys specialisation — pick the quant, then tune

> **Status:** open. **No implementation yet.** This is a handover to a fresh
> session. It states the goal, the facts already gathered, the approach, and the
> open questions. Read it end to end before you touch a file.

## Context

brys already serves two mutually exclusive boot specialisations through the
standalone `kdn.llm.local` slot (see [docs/local-llms.md](../../../docs/local-llms.md)):

- `llm-ds4` (`hosts/brys/llm-ds4.nix`) — DeepSeek V4 Flash alone, 320K shared
  unified KV, 4 slots.
- `llm-small` (`hosts/brys/llm-small.nix`) — the small-model set alone.

This task adds a **third** specialisation for **Qwen3.8-Flash-Next**, a newer,
much sparser model. The goal is a boot-selected appliance that serves it alone,
a measured best-fit quant, and a tuning pass in practice.

## Goal

1. Choose the quant that fits brys best and download it.
2. Wire it as a new boot specialisation, in the shape of `llm-ds4` / `llm-small`.
3. Cold-boot it, verify it serves over the LAN endpoint, and measure it.
4. Fine-tune it in practice (context, batch, threads, slots, speculative
   decoding) and record the results in [docs/local-llms.md](../../../docs/local-llms.md).

## Hardware (brys)

- Ryzen 9 5950X (16C/32T), 128 GB DDR4, ~40 GB/s COPY, Radeon Pro W6600
  (useless for this workload).
- The ZFS ARC is capped at 8 GiB (`zfs.zfs_arc_max=8589934592`) in
  `hosts/brys/llm.nix`; the cap is a cold-boot kernel parameter.
- Reference: DeepSeek V4 Flash runs at ~101 GB of `mmap`'d weights plus
  ~15 GB KV/anon → ~115 GB RSS, and it holds. Treat ~104 GB of weights as the
  proven ceiling for a single resident model.

## Model facts (gathered 2026-10-06)

- Base repo: `Qwen/Qwen3.8-Flash-Next`. Architecture `Qwen4ExpForConditionalGeneration`
  (`model_type: qwen4_exp`). `image-text-to-text` (multimodal, needs `mmproj` for vision).
- **Not 180B dense.** The ~180B total splits into a **125B main model with ~6B
  active per token**, a **51B n-gram embedding table**, and a **~4B MTP head**
  (Kagi thread, Atomic Chat / Unsloth). Text config: 48 layers, hidden 2560,
  **512 experts with 10 active per token** plus a shared expert. **GDN + QSA
  hybrid attention** (linear + full), `max_position_embeddings` 262144 (256K), 2
  KV heads.
- **The n-gram table is a lookup, not compute** (~2.7 KB read per token). It can
  live on SSD instead of RAM — but only if the quant keeps it in its own shard.
  **Unsloth's builds keep it inside the weight shards** (whole file resident);
  **Atomic Chat's builds separate it** (its 4.27 bpw build needs ~54.5 GB RAM
  with ~38.4 GB paged from SSD, freeing ~40 GB).
- **llama.cpp support is recent.** Added by PR #27742, merged 2026-08-27. Verify
  that the pinned `llama-cpp` 0.4.0 (build 10809) actually loads `qwen4exp`
  before the full download — a common error is `unknown model architecture:
  'qwen4exp'` on an older build.
- GGUF source: `unsloth/Qwen3.8-Flash-Next-GGUF`; alternative
  `Atomic Chat` (AD-4.27bpw, n-gram on SSD).

### Quant candidates

Two size figures exist. The Kagi thread uses Unsloth's published table (which
runs larger); the second column is this repo's measured shard totals from the HF
API on 2026-10-06.

| quant | Kagi/Unsloth | measured | top-1 vs BF16 | note |
|---|---|---|---|---|
| `Q8_0` | — | 175.3 GB | — | does not fit |
| `UD-Q5_K_XL` | — | 147.4 GB | — | does not fit |
| `UD-Q4_K_XL` | 111.3 GB | 103.7 GB | 92.3% | **tight** at full context (~123 GiB with OS+KV) |
| `UD-IQ4_XS` | 93.7 GB | 87.2 GB | 89.6% | **primary candidate** — good balance |
| `UD-Q3_K_XL` | 90.0 GB | 83.8 GB | 88.3% | comfortable |
| `UD-IQ3_XXS` | 82.0 GB | 76.3 GB | 85.4% | comfortable, most KV room |
| `UD-Q2_K_XL` | — | 73.5 GB | — | low |
| `UD-IQ1_M` | — | 69.4 GB | — | very low |
| `UD-IQ1_S` | — | 67.6 GB | — | very low |

**Start with `UD-IQ4_XS`**, not `UD-Q4_K_XL`: the Kagi thread's recommendation is
IQ4_XS with **F16 KV** and a context of **128K–200K**. Q4_K_XL is tight once the
OS and KV are counted. The sparse MoE makes decode bandwidth-bound on the active
experts, so residency and prefill are the constraints, not compute.

### Expected speed (CPU-only, from the Kagi thread; verify on brys)

| config | generation | prefill |
|---|---|---|
| `IQ3_XXS` / `Q3_K_XL` | ~8–11 tok/s | ~20–40 tok/s |
| `IQ4_XS` / `Q4_K_XL` | ~6–9 tok/s | ~20–40 tok/s |
| 70K+ context depth | roughly half | lower still |

Reference points: a near-twin 5950X + RTX 3090 Ti at Q4_K_XL reached 15 tok/s at
30K context and ~340 tok/s prefill; a CPU-only Core Ultra 9 285K reached
~10–11.5 tok/s generation at 2-bit. **Prefill is the weak point for agentic
coding** — a 50K-token prompt could take tens of minutes on CPU alone.

## Proposed approach

1. **Add the model** to a new `hosts/brys/llm-qwen.nix` specialisation. Reuse
   `hosts/brys/llm-appliance.nix` and the shared `nixos` block of
   `hosts/brys/llm.nix` (secrets, persistence, leaf key, ARC cap). The current
   `llm.nix` hardcodes DS4 and the small set behind `withFrontier` / `withSmall`;
   the clean route is either a third flag there or a dedicated slot builder in
   `llm-qwen.nix`. Decide and record why.
2. **Wire the download.** `kdn.llm.local.models.<name>` takes `hfRepo`, `hfFile`,
   `download.glob` (for shards), `download.minBytes`, and `perf.*`. Fetch all
   shards with a glob, e.g.
   `UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-*.gguf`, first shard as `hfFile`.
   The download is ~87–94 GB — run it through `kdn-llm-download` and confirm the
   tree is complete before you boot.
3. **Register the boot entry.** Add `specialisation.llm-qwen` in
   `hosts/brys/default.nix`, beside `llm-ds4` and `llm-small`.
4. **Deploy and cold-boot** (the sanctioned flow):
   ```shell
   ./nixos-rebuild.sh boot remote=brys
   ./select-boot-entry.sh brys llm-qwen --reboot
   ```
5. **Verify** over the LAN endpoint (`https://brys.priv.nb.net.int.kdn.im/v1`,
   key at `/run/configs/llms/llama-server/api-keys/default`), then measure.
6. **Fine-tune** and record each result in the benchmark log.

## Tuning levers to test

The values below come from the Kagi thread's Flash-Next section. The thread is
**old and theoretical**; treat every number as a hypothesis to verify on brys,
not a fact.

- **Context** (`perf.contextSize`): 256K is the model max; the thread suggests
  **128K–200K**. KV is the headroom cost.
- **KV cache**: the thread reports **quantized KV (`q8_0`) is buggy for this
  model** (assertion failure, reasoning loops). Use **F16 KV**.
- **Slots**: the thread says `--parallel 1` — the patched QSA cache works for a
  single slot only. Verify before trying the DS4 `parallel 4` shape.
- **Batch / ubatch** (`perf.batchSize`, `perf.ubatchSize`): the thread suggests
  `-b 2048 -ub 1024`, and a rule `ub × ctx < ~540M`. Re-measure for this model.
- **Threads** (`perf.threads`): 16 physical cores. The DS4 note says no CPU
  affinity (llama-cpp 0.4.0 stalls prefill with `--cpu-range`).
- **Flags**: `-fit off`, `--jinja`, mmap on. For an Atomic Chat build (n-gram in
  its own shard), `--lazy-mode on` keeps the n-gram shard on SSD; never combine
  it with `--load-mode none`. The slot may need new `perf.*` options for these.
- **Thinking**: the model thinks a lot; the thread suggests `reasoning_effort`
  medium.
- **Speculative decoding**: the MTP head needs a custom llama.cpp PR. A 5950X
  user got by with `--spec-type ngram-mod` instead. Investigate what build 10809
  supports, or leave it off.
- **Vision**: the `mmproj-F16.gguf` (0.8 GB) is out of scope for the first pass;
  the slot has no `mmproj` option today. Note it as a follow-up.

## Acceptance criteria

- The new specialisation boots and serves the model over the LAN endpoint.
- The chosen quant stays resident: `RssFile` steady, idle major faults ~0, no
  OOM, healthy `MemAvailable`.
- Prefill and decode rates recorded against the `llm-ds4` baseline.
- A short concurrency check (two requests, neither waits for the other) if
  `parallel > 1`.
- The measured rows and the chosen quant written into
  [docs/local-llms.md](../../../docs/local-llms.md).
- A `done.md` when the specialisation is verified; otherwise a `status.md`.

## Open questions

- Exact llama.cpp support for this architecture (`qwen4_exp`, GDN+QSA hybrid
  attention, MTP) at build 10809. Verify the model loads at all before the full
  download, e.g. a small quant first, or a load-only test. Known risks from the
  thread: a QSA-indexer long-context slowdown, a livelock on load, and an
  `unknown model architecture: 'qwen4exp'` error on older builds.
- Which quant: `UD-IQ4_XS` (primary) vs `UD-Q3_K_XL`/`UD-IQ3_XXS` (more KV room)
  vs `UD-Q4_K_XL` (tight) under the 8 GiB ARC cap.
- Which build: Unsloth (n-gram inside the weight shards) vs Atomic Chat (n-gram
  in its own shard, ~40 GB freed, needs `--lazy-mode on`).
- Does the MTP head work as `--model-draft`, is `--spec-type ngram-mod` the
  route, or is neither supported at build 10809?
- Does the sparse MoE decode actually beat DS4's measured ~5–7 tok/s, and by how
  much? Does the hybrid-attention serial overhead hurt it (cf. `qwen3-next-80b`)?
- Whether the model should replace DS4 as the frontier, or stay a separate entry.

## References

- **Kagi Assistant thread** (external research; read 2026-10-06 from
  `/tmp/70ca2478-…md`): `https://assistant.kagi.com/chat/70ca2478-7e57-4dc7-9f7a-d555b5229e21`.
  **Old and theoretical.** Only the last turns (Qwen3.8-Flash-Next on this
  hardware) were used here. Its claims about the existing models and config are
  superseded by measured practice and must not be trusted.
- [docs/local-llms.md](../../../docs/local-llms.md) — the deployment, the ZFS ARC
  quirk, the prefill tuning, the benchmark log, and the client tiers.
- [hosts/brys/llm.nix](../../../../hosts/brys/llm.nix) — the shared slot wiring
  (`withFrontier` / `withSmall`).
- [hosts/brys/llm-appliance.nix](../../../../hosts/brys/llm-appliance.nix) — the
  shared boot body.
- [hosts/brys/llm-ds4.nix](../../../../hosts/brys/llm-ds4.nix) and
  [hosts/brys/llm-small.nix](../../../../hosts/brys/llm-small.nix) — the two
  existing specialisations to copy.
- [modules/slots/llm/default.nix](../../../../modules/slots/llm/default.nix) —
  the slot options (`models.*`, `perf.*`, `download.*`).
- `.brys-optimization.md` (git-ignored) — the append-only worklog of the DS4
  tuning, including every measured lever.
- HuggingFace: `Qwen/Qwen3.8-Flash-Next` (config),
  `unsloth/Qwen3.8-Flash-Next-GGUF` (quants).
- Key thread sources: llama.cpp PR #27742 (support, merged 2026-08-27); Unsloth
  docs `unsloth.ai/docs/models/qwen3.8-next`; Atomic Chat GGUF guide
  (`atomic.chat/blog/guides/how-to-run-qwen-3-8-flash-next-locally`).

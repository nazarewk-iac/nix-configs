---
type: Task
description: Add the latest llama.cpp release and the Unsloth MTP fork as in-repo packages, so brys can benchmark qwen4exp speculative decode against the pinned 0.4.0.
status: in-progress
authored_by: agent
timestamp: 2026-10-07T08:10:00+02:00
---

# llama.cpp: latest release and the Unsloth MTP fork

## Goal

Add two in-repo llama.cpp builds from source:

1. `llama-cpp-v0_6_0` — the ggml-org v0.6.0 release.
2. `llama-cpp-unsloth-mtp` — the Unsloth fork branch `qwen4exp/mtp`.

Then benchmark Qwen3.8-Flash-Next (`qwen4exp`) decode on brys against the pinned
nixpkgs build.

## Context

- The pinned nixpkgs `llama-cpp` is 0.4.0, build 10809, commit 5266f24. That
  build does not contain the merged `qwen4exp` MTP graph. Speculative decode
  cannot use the model MTP head.
- ggml-org v0.6.0 (build 11429, commit d812350, published 2026-10-05) merges MTP
  for `qwen4exp` (PR #29761) and the mask/indexer performance fixes. The PR
  reports about 1.55x decode.
- The Unsloth fork `danielhanchen/llama.cpp`, branch `qwen4exp/mtp` (head
  6fcaa16, base version 0.4.1), is the build the Unsloth docs name. It has an
  older base and reported regressions, but the user wants it for comparison.
- brys serves these models on the CPU alone, with 16 physical cores. The GPU
  does not help this workload. See [hosts/brys/llm.nix](../../../../hosts/brys/llm.nix).
- The bring-up task that found the gap:
  [docs/tasks/2026-10/qwen-flash-next-quant/definition.md](../qwen-flash-next-quant/definition.md).

## The two derivations

`packages/llama-cpp/default.nix` holds both. Each derivation builds from source
with a pinned `fetchFromGitHub` source. The attribute `llama-cpp-v0_6_0` uses
underscores, because a dot is not a valid Nix attribute name.

Both builds drop the embedded web UI. The server API, the MTP graph and
`--help` do not need the UI. This choice removes the npm dependency tree and
its `npmDepsHash`, and it shortens the build. Each build is CPU-only, with all
CPU variants for runtime dispatch.

The packages are reachable as:

- `pkgs.kdn.llama-cpp-v0_6_0` and flake `packages.<system>.llama-cpp-v0_6_0`
- `pkgs.kdn.llama-cpp-unsloth-mtp` and flake
  `packages.<system>.llama-cpp-unsloth-mtp`

## Benchmark plan (brys)

1. Build both derivations. Confirm that each `llama-server --help` lists
   `draft-mtp`.
2. Serve `unsloth/Qwen3.8-Flash-Next-GGUF` UD-IQ4_XS through the `llm-qwen`
   boot specialisation.
3. Measure decode three times: with the pinned 0.4.0, with v0.6.0, and with the
   Unsloth fork. Hold the context, batch/ubatch and thread settings constant.
4. Record every result in [docs/local-llms.md](../../../local-llms.md).

## Results (brys, 2026-10-07)

Warm run, 300-token decode, ctx 131072, batch/ubatch 4096, threads 16,
parallel 1. The `control` is the pinned nixpkgs 0.4.0.

| config | package | MTP | prefill t/s | decode t/s | MTP acceptance | RSS | idle maj_fault/s |
|---|---|---|---|---|---|---|---|
| control | 0.4.0 b10809 | no | 36.6 | 5.65 | — | 82.3 GiB | 0 |
| A | 0.6.0 b11429 | no | 37.7 | 5.81 | — | 81.3 GiB | 0 |
| B | 0.6.0 b11429 | yes | 35.2 | 9.50 | 1.000, mean len 2.99 | 87.8 GiB | 0 |
| C | unsloth b11098 | yes | 36.8 | 9.56 | 1.000, mean len 2.99 | 86.6 GiB | 0 |

Findings:

- MTP gives about +68% decode (5.65 to about 9.5 t/s).
- v0.6.0 without MTP is within noise of 0.4.0.
- C (the fork) and B (upstream) are within about 1-4% of each other. The
  difference is noise.
- No run hit OOM.

The deployed package is **`llama-cpp-v0_6_0`** (config A/B) with MTP on, not C.
v0.6.0 carries the long-context QSA indexer memory and mask fixes that the
Unsloth fork lacks, so it is the build for the 1M-context work. The fork's short
decode edge (9.56 vs 9.50 t/s) is noise and does not outweigh those fixes. See
`hosts/brys/llm-qwen.nix` and the long-context ladder in
[docs/local-llms.md](../../../local-llms.md).

## Update procedure

See [packages/llama-cpp/README.md](../../../../packages/llama-cpp/README.md) for
the exact steps to bump each derivation: find the new target, get the source
hash, edit the fields, build and verify, and deploy to brys.

## Open question: upstreaming vs override

The build works and brys deploys it. One question stays open: does the MTP graph
go upstream, or does brys keep the local override?

- Upstream route: wait for the release to reach nixpkgs, then drop the custom
  derivation. The MTP change already merged upstream (PR #29761), so this route
  is plausible.
- Override route: keep `packages/llama-cpp` and select it per host.

Until the decision lands, brys keeps the local override.

## Acceptance criteria

- Both derivations build and expose the `draft-mtp` spec type.
- Each binary contains the `qwen4exp` model and the MTP graph.
- Decode is benchmarked against 0.4.0, and the numbers are recorded.
- A decision is recorded: brys keeps a local override, or the change goes
  upstream.

## References

- llama.cpp PR #29761 — merged MTP for `qwen4exp`.
- ggml-org llama.cpp v0.6.0 release (build 11429, commit d812350).
- Unsloth fork branch `qwen4exp/mtp`:
  <https://github.com/danielhanchen/llama.cpp/tree/qwen4exp/mtp>.
- Unsloth docs `unsloth.ai/docs/models/qwen3.8-next`.
- [docs/local-llms.md](../../../local-llms.md) — the deployment, the tuning and
  the benchmark log.
- [hosts/brys/llm.nix](../../../../hosts/brys/llm.nix) — the shared slot wiring.
- [packages/llama-cpp/default.nix](../../../../packages/llama-cpp/default.nix) —
  the two derivations.
- [packages/llama-cpp/README.md](../../../../packages/llama-cpp/README.md) —
  how to update the two derivations.
- [status.md](status.md) — the paused checkpoint (packaging done, upstreaming
  open).

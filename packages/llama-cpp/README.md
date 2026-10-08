# Updating the llama.cpp builds

This directory holds llama.cpp builds from source, for the Qwen3.8-Flash-Next
(`qwen4exp`) work on brys:

| Attribute | Source | Version | Build | Commit | Backend |
|---|---|---|---|---|---|
| `llama-cpp-v0_6_0` | `ggml-org/llama.cpp` | 0.6.0 | 11429 | `d812350` | CPU |
| `llama-cpp-v0_6_0-vulkan` | `ggml-org/llama.cpp` | 0.6.0 | 11429 | `d812350` | CPU + Vulkan |
| `llama-cpp-v0_6_0-vulkan-noblas` | `ggml-org/llama.cpp` | 0.6.0 | 11429 | `d812350` | CPU + Vulkan, no BLAS |
| `llama-cpp-master-vulkan` | `ggml-org/llama.cpp` master | 0.6.0-unstable-2026-10-08 | 11490 | `9c2e0e4` | CPU + Vulkan |
| `llama-cpp-master-noprefetch-vulkan` | the same master + PR #29250 | 0.6.0-unstable-2026-10-08 | 11490 | `9c2e0e4` | CPU + Vulkan |
| `llama-cpp-master-moe-stream-vulkan` | the same master + PR #25294 | 0.6.0-unstable-2026-10-08 | 11490 | `9c2e0e4` | CPU + Vulkan |
| `llama-cpp-master-pin-hot-experts-vulkan` | the same master + PR #26414 | 0.6.0-unstable-2026-10-08 | 11490 | `9c2e0e4` | CPU + Vulkan |
| `llama-cpp-unsloth-mtp` | `danielhanchen/llama.cpp`, branch `qwen4exp/mtp` | 0.4.1 | 11098 | `6fcaa16` | CPU |

The `master` rows are experiments, not served builds. The `master-vulkan` and
`master-noprefetch-vulkan` rows test whether a
newer llama.cpp or `--no-mmap-prefetch` removes the ~140 s first-request stall
of Qwen3.8-Flash-Next on brys. The result is negative: the stall is cold-cache
read bound, not prefetch bound; the prefetch at load actually warms the cache
and lowers the first-request time. `--no-mmap-prefetch` shortens the load
(140 s to 84 s) but lengthens the first request (142 s to 192 s) and lowers
steady decode (4.2 to 2.4 t/s). `--load-mode none` crashes the W6600
(`amdgpu: Not enough memory for command submission`). Neither build is selected
by any host. See [docs/tasks/2026-10/llama-cpp-latest-package/](../../docs/tasks/2026-10/llama-cpp-latest-package/)
and the benchmark in [docs/local-llms.md](../../docs/local-llms.md).

The pinned nixpkgs `llama-cpp` is 0.4.0 (build 10809). That build has no
`qwen4exp` MTP graph, so the server cannot use the model MTP head. The
derivations above add the MTP graph. Every build drops the embedded web UI on
purpose. See [default.nix](default.nix) for the build flags.

## The Vulkan variant

`llama-cpp-v0_6_0-vulkan` is the same v0.6.0 source with `GGML_VULKAN` on. It
adds `shaderc` (native), `vulkan-headers`, `vulkan-loader` and `spirv-headers`.
`GGML_CPU_ALL_VARIANTS` and `GGML_BACKEND_DL` stay true, so the CPU keeps every
expert and the KV cache and Vulkan offloads the dense layers only. This is the
build for the Radeon Pro W6600 (`gfx1032`) on brys. Build it with:

```bash
nix build .#llama-cpp-v0_6_0-vulkan --no-link
```

The build compiles the whole Vulkan shader set, so it is much slower than the
CPU-only build. To use it, the host must expose the Mesa RADV Vulkan ICD (see
`hardware.graphics.enable` and `hardware.graphics.extraPackages`). The GPU
device is selected at runtime; on a two-GPU host set `MESA_VK_DEVICE_SELECT` to
the wanted `vendor:device` pair. The GPU-offload specialisation and the smoke
test are recorded in
[docs/tasks/2026-10/qwen-gpu-offload/definition.md](../../docs/tasks/2026-10/qwen-gpu-offload/definition.md).

The task that added these builds:
[docs/tasks/2026-10/llama-cpp-latest-package/definition.md](../../docs/tasks/2026-10/llama-cpp-latest-package/definition.md).
The deployment and the benchmark log:
[docs/local-llms.md](../../docs/local-llms.md).

## The no-BLAS variant

`llama-cpp-v0_6_0-vulkan-noblas` is the same v0.6.0 Vulkan source with
`GGML_BLAS=false` and no OpenBLAS input. It drops `bin/libggml-blas.so`, so the
CPU uses the ggml CPU backend for the dense-layer matmuls. Build it with:

```bash
nix build .#llama-cpp-v0_6_0-vulkan-noblas --no-link
```

The BLAS backend dequantizes a quantized `src0` to F32 and calls `cblas_sgemm`.
On brys that stalls small fresh prompts: a 124-token fresh prefill ran at
1.0 t/s with BLAS against 10.3-17.7 t/s without (a 10-16x stall). The stall is
specific to small prompts. A 2K prefill is 1.6x and a 16K prefill 1.2x faster
without BLAS, and a 300-token decode is about 30% faster. `qwenGpu` in
[hosts/brys/llm.nix](../../hosts/brys/llm.nix) now defaults to this build, so
`llm-qwen` and `llms-frontier` use it. The full A/B is in
[docs/local-llms.md](../../docs/local-llms.md).

## Expert-streaming experiments (negative)

Two further master builds test whether streaming the MoE routed-expert weights
from disk lowers the RAM of the mostly-resident model. Both are manual ports of
open upstream PRs onto master `9c2e0e4`, carried as patch files in this
directory. They are kept only as a record. **No host selects them.**

| Attribute | PR | Flags | Patch |
|---|---|---|---|
| `llama-cpp-master-moe-stream-vulkan` | #25294 | `--moe-stream`, `--moe-stream-cache <NG\|Ns>`, `--moe-stream-io-threads N`, `--moe-stream-direct` (O_DIRECT) | `25294-moe-stream.patch` |
| `llama-cpp-master-pin-hot-experts-vulkan` | #26414 | `--pin-hot-experts N`, `--pin-hot-experts-budget-mib N`, `--load-mode mmap+pin` | `26414-pin-hot-experts.patch` |

`--moe-stream` reads the routed-expert weights from disk on demand and
auto-disables mmap. `--pin-hot-experts` mlock's the N hottest experts per layer
so the page cache cannot evict them.

Benchmark on brys: the served `llm-qwen` shape (Qwen3.8-Flash-Next `UD-IQ4_XS`,
1M ctx YaRN x4, F16 KV, W6600 MTP draft, `parallel 4 --kv-unified`). The page
cache was dropped before each run. The baseline is master or v0.6.0 with no
flag; the two match.

| build / flag | steady decode | prefill | RSS |
|---|---|---|---|
| baseline (master or v0.6.0) | ~4.68 t/s | ~16.5 t/s | ~91 GiB |
| master + `--moe-stream --moe-stream-direct --moe-stream-cache 64s` | 3.10 t/s (−34%) | 5.7 t/s (−65%) | ~41 GiB |
| master + `--pin-hot-experts` | = baseline | = baseline | ~91 GiB |

Verdict: **expert streaming hurts when the model is mostly resident.** The
weights already fit in ~75% of the 125 GB RAM, so the page cache serves them.
`--moe-stream-direct` (O_DIRECT) bypasses that cache, and every step becomes
storage-bound. The RAM drop is real (~41 GiB), but the throughput loss is not
worth it. `--pin-hot-experts` is a no-op on this model (see below). The
first-request latency is unchanged (~150 s cold-read stall, reproduced).

Bugs found:

- **#25294, under-sized default expert cache.** The default is
  `n_slots = 2*n_expert_used = 20`, but the multi-pass prefill path needs
  `>= 3*n_expert_used = 30`. The context fails at init with `GGML_ABORT` unless
  `--moe-stream-cache 64s` is set.
- **#26414, no `qwen4exp` match.** The `ffn_moe_topk` callback does not match
  `qwen4exp`, so the build prints `no MoE layers detected in model` and has no
  effect.

Skipped PRs, with reasons:

| PR | Reason |
|---|---|
| #26003 `--lazy-experts` | closed, not merged |
| #29191 | needs an external `guanaco/` library; not buildable |
| #27861 | superseded by master's GPU `--moe-cache-mib` |
| #28414, #29250 | draft, or already tested (see "The first-request stall") |

## Find the new target

### Upstream (ggml-org)

1. Open <https://github.com/ggml-org/llama.cpp/releases>.
2. Read the newest release tag. The tag encodes the build number, for example
   `b11429`.
3. Read the commit of that tag. Run this command, and use the `^{}` line:

   ```bash
   git ls-remote https://github.com/ggml-org/llama.cpp 'refs/tags/b11429*'
   ```

### Fork (danielhanchen)

Read the branch head. The output gives the commit:

```bash
git ls-remote https://github.com/danielhanchen/llama.cpp refs/heads/qwen4exp/mtp
```

## Get the source hash

Run `nix-prefetch-github`. The `hash` field in the JSON output is the SRI hash
that `default.nix` needs:

```bash
nix-prefetch-github ggml-org llama.cpp --rev <rev>
```

If `nix-prefetch-github` is not on the PATH, run it through nixpkgs:

```bash
nix run nixpkgs#nix-prefetch-github -- ggml-org llama.cpp --rev <rev>
```

For the fork, change the owner and the repo:

```bash
nix run nixpkgs#nix-prefetch-github -- danielhanchen llama.cpp --rev <rev>
```

Alternative: run `nix build` with the old hash. The build fails and prints the
correct hash on a line that starts with `got:`.

## Edit the derivation

Open [default.nix](default.nix). For `llama-cpp-v0_6_0`, edit these fields:

- `version`
- `buildNumber`
- `buildCommit`
- `src.rev`
- `src.hash`

For `llama-cpp-unsloth-mtp`, edit the same fields. Edit `pname` too, because the
fork keeps its own attribute name.

## Build and verify

Build each attribute, and confirm that it succeeds:

```bash
nix build .#llama-cpp-v0_6_0 --no-link
nix build .#llama-cpp-unsloth-mtp --no-link
```

Read the version string:

```bash
out=$(nix build .#llama-cpp-v0_6_0 --no-link --print-out-paths)
$out/bin/llama-server --version
```

Check for the MTP graph. The command must find at least one `qwen4exp` MTP
symbol:

```bash
nm -D --defined-only $out/lib/libllama.so.0.* | grep -i 'qwen4exp.*mtp'
```

## Deploy to brys

The `llm-qwen` boot specialisation selects the fork build. Rebuild the boot
entries, then select the entry and reboot:

```bash
./nixos-rebuild.sh boot remote=brys
./select-boot-entry.sh brys llm-qwen --reboot
```

The build needs about 4 minutes on this CPU-only host. The UI is off on purpose,
so the build does not need npm or its `npmDepsHash`.

## Other update mechanisms

- **The nixpkgs master input.** The flake pins nixpkgs. A newer nixpkgs can
  already hold the wanted version. Prefer this route when a release reaches
  nixpkgs. Then delete the matching custom derivation and use `pkgs.llama-cpp`.
- **A `.flake.patches` bump.** A patch under [.flake.patches](../../.flake.patches)
  can change the nixpkgs `llama.cpp` in place. Prefer this route for a small
  change to the pinned build. See
  [.flake.patches/config.toml](../../.flake.patches/config.toml) for the
  `[patch.<input>.<name>]` entries.

Prefer a custom derivation only while the wanted release is not in nixpkgs.

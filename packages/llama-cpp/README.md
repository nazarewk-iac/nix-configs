# Updating the llama.cpp builds

This directory holds llama.cpp builds from source, for the Qwen3.8-Flash-Next
(`qwen4exp`) work on brys:

| Attribute | Source | Version | Build | Commit | Backend |
|---|---|---|---|---|---|
| `llama-cpp-v0_6_0` | `ggml-org/llama.cpp` | 0.6.0 | 11429 | `d812350` | CPU |
| `llama-cpp-v0_6_0-vulkan` | `ggml-org/llama.cpp` | 0.6.0 | 11429 | `d812350` | CPU + Vulkan |
| `llama-cpp-unsloth-mtp` | `danielhanchen/llama.cpp`, branch `qwen4exp/mtp` | 0.4.1 | 11098 | `6fcaa16` | CPU |

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

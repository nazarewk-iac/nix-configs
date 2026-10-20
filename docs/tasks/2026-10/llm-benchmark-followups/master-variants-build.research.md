---
type: Research
description: Build test of the four experimental llama.cpp master Vulkan variants (base, no-mmap-prefetch, moe-stream, pin-hot-experts) from packages/llama-cpp/default.nix. All four build, the three patches apply, and the expected flags are present.
task: definition.md
authored_by: agent
timestamp: 2026-10-20T01:34:04+02:00
---

# Build of the llama.cpp master Vulkan variants

This document answers item F3 of the task, first part: do the four master
variants build? The four variants come from
[packages/llama-cpp/default.nix](../../../../packages/llama-cpp/default.nix).
They share the same source (ggml-org master, build 11490, commit `9c2e0e4`,
2026-10-08) and the same flags, and only the patch set differs. The task does
not test on `brys` here. A later task does that.

## Method

- Host: this repository's x86_64-linux host. `max-jobs` is 16. No x86_64-linux
  remote builder is configured, so every build ran locally.
- Build command, one variant per run:

  ```bash
  nix build --no-write-lock-file --impure --no-link --print-out-paths --expr \
    'let f=builtins.getFlake (toString ./.);
         p=f.inputs.nixpkgs.legacyPackages.x86_64-linux.extend f.overlays.default;
     in p.kdn.<variant>'
  ```

- Each variant built in about 5 minutes (292 s to 296 s). The whole set built in
  20 minutes. No patch failed.
- The flag check is `llama-server --help | grep -iE
  "moe-stream|pin-hot|no-mmap-prefetch|load-mode"`.

## Results

| Variant | Patch | Builds? | Store path | Flags present | Note |
|---|---|---|---|---|---|
| `llama-cpp-master-vulkan` | none (control) | yes, exit 0 | `/nix/store/is3isrxbkmbmkw82nb82v90nrf5yimz1-llama-cpp-master-vulkan-0.6.0-unstable-2026-10-08` | `--load-mode` | The base source builds. A patched failure below is not the base source. |
| `llama-cpp-master-noprefetch-vulkan` | `29250-no-mmap-prefetch.patch` | yes, exit 0 | `/nix/store/36laj0v3hicp7gk9ilbv4s7r9a0fa76i-llama-cpp-master-noprefetch-vulkan-0.6.0-unstable-2026-10-08` | `--no-mmap-prefetch`, `--load-mode` | The patch applies. |
| `llama-cpp-master-moe-stream-vulkan` | `25294-moe-stream.patch` | yes, exit 0 | `/nix/store/zr6mk40vdj1aspw1r4ms7cklsmkj7927-llama-cpp-master-moe-stream-vulkan-0.6.0-unstable-2026-10-08` | `--moe-stream`, `--moe-stream-cache <NG\|Ns>`, `--moe-stream-io-threads N`, `--moe-stream-direct`, `--load-mode` | The manual port applies. |
| `llama-cpp-master-pin-hot-experts-vulkan` | `26414-pin-hot-experts.patch` | yes, exit 0 | `/nix/store/s19bsy6yi4p9l114d49m5qqq4v9cqvz9-llama-cpp-master-pin-hot-experts-vulkan-0.6.0-unstable-2026-10-08` | `--pin-hot-experts N`, `--pin-hot-experts-budget-mib N`, `--pin-hot-experts-stats-interval N`, `--load-mode mmap+pin` | The manual port applies. |

Every binary reports the same version:

```
version: 0.6.0 (build 11490, commit 9c2e0e4)
built with GNU 16.2.0 for Linux x86_64
```

## Flags for the brys test

The flags below are present in the built binaries and are ready for the brys
measurement.

- `llama-cpp-master-noprefetch-vulkan`: `--no-mmap-prefetch`. It keeps mmap on,
  but it skips the blocking `MADV_WILLNEED` prefetch of the whole model file.
- `llama-cpp-master-moe-stream-vulkan`: `--moe-stream`,
  `--moe-stream-cache <NG|Ns>`, `--moe-stream-io-threads N`,
  `--moe-stream-direct`. The flag reads the routed-expert weights from disk on
  demand and turns mmap off.
- `llama-cpp-master-pin-hot-experts-vulkan`: `--pin-hot-experts N`,
  `--pin-hot-experts-budget-mib N`, `--pin-hot-experts-stats-interval N`, and
  the `--load-mode mmap+pin` mode. The flags lock the N hottest experts per
  layer in RAM.

The control `llama-cpp-master-vulkan` has only `--load-mode` (auto, none, mmap,
mlock, mmap+mlock, dio). Use it as the baseline.

## Notes

- The control build shows that the base master source still builds. Therefore a
  future patch failure is a patch problem, not a base-source problem.
- The three patches are manual ports onto master `9c2e0e4`. They still apply and
  compile on 2026-10-20. If master moves and the patch context changes, expect a
  patch failure. Rebase the patch then.
- No Nix configuration changed. No patch rebase was necessary.

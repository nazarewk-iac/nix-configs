---
type: Solution
description: Added the llm-qwen-gpu boot specialisation; the intended dense-layer offload is slower than CPU, so the final config offloads only the MTP draft head to the W6600 for +18.5% decode.
task: definition.md
authored_by: agent
timestamp: 2026-10-07T14:40:00+02:00
---

# Solution — Qwen3.8-Flash-Next on the W6600

## Root cause analysis

The task first assumed that offloading the dense layers helps, because the dense
weights are about 80% of the bytes one decode token reads. The measurement shows
the opposite.

At 1M context the F16 KV cache is about 24 GiB. It cannot fit in the 8 GB W6600,
so it must stay on the CPU (`-nkvo`). When llama.cpp also puts the attention
layers on the GPU (`-ngl 99`), every attention step must read the CPU-resident
KV across PCIe. That transfer dominates, and decode falls to **2.0 t/s** (from
9.1 on the CPU). The same happens with `-ot "ffn_.*_exps=CPU"` instead of
`-cmoe`, and with a partial `-ngl` (5.0-5.9 t/s). A partial `-ngl` without
`-cmoe` also puts the big expert tensors on the GPU and fills VRAM.

The MTP draft head is about 6 GB and runs five times per speculative step. It
fits in the W6600 on its own. Moving only the draft to the GPU keeps the main
model and its KV together in RAM and removes the draft's CPU cost. This is the
only variant that beats the CPU baseline.

## Solution

Slot and den aspect gain five `perf.*` keys, each emitted only when set
(`modules/slots/llm/default.nix`, `modules/den/aspects/llm.nix`):

- `nGpuLayers` (`nullOr int`) -> `n-gpu-layers = <n>`
- `cpuMoe` (`bool`) -> `cpu-moe = on`
- `noKvOffload` (`bool`) -> `no-kv-offload = on`
- `draftNGpuLayers` (`nullOr int`, with `draft.enable`) -> `n-gpu-layers-draft = <n>`
- `device` (`nullOr str`) -> `device = <v>`

The key names are the long options of the v0.6.0 preset parser
(`common/preset.cpp` builds its map from each option's arguments), so all five
are accepted.

`hosts/brys/llm.nix` exposes them as `qwenNGpuLayers`, `qwenCpuMoe`,
`qwenNoKvOffload`, `qwenDraftNGpuLayers`, `qwenDevice`.

`hosts/brys/llm-qwen-gpu.nix` mirrors `hosts/brys/llm-qwen.nix` with:

```nix
llamaPackage = pkgs.kdn.llama-cpp-v0_6_0-vulkan;
qwenMtp = true;
qwenSpecDraftNMax = 5;
qwenDraftNGpuLayers = 99;   # draft head on the W6600
qwenDevice = "Vulkan0";     # never the 4 GB Lexa (Vulkan1)
qwenContextSize = 1048576;  # YaRN x4, same as llm-qwen
```

`llm-appliance.nix` gained an `extraConfig` argument. The GPU entry uses it for
the runtime-only bits:

```nix
hardware.graphics.enable = true;
hardware.graphics.extraPackages = [ pkgs.mesa ];
systemd.services.llama-cpp.environment.MESA_VK_DEVICE_SELECT = "1002:73e3!";
```

`hosts/brys/default.nix` registers `specialisation.llm-qwen-gpu` beside
`llm-qwen`. The `llm-appliance.nix` header count went three -> four.

## Verification steps

Build, deploy, boot:

```bash
nix build '.#nixosConfigurations.brys.config.system.build.toplevel' --no-link --keep-going
./nixos-rebuild.sh boot remote=brys
./select-boot-entry.sh brys llm-qwen-gpu --reboot
```

Observed on brys:

```
$ cat /run/current-system/nixos-version
llm-qwen-gpu-26.11.20260908.d6524aa
$ systemctl is-active llama-cpp
active
$ <vulkan-build>/bin/llama-server --list-devices
  Vulkan0: AMD Radeon Pro W6600 (RADV NAVI23) (8176 MiB, 8128 MiB free)
  Vulkan1: AMD Radeon RX 550 / 550 Series (RADV POLARIS12) (4096 MiB, ...)
```

The router child args show the placement:

```
--device Vulkan0 ... --n-gpu-layers-draft 99 ... --model-draft .../mtp-...Q8_0.gguf
```

The generated preset INI (`models-preset.ini`) holds `device = Vulkan0` and
`n-gpu-layers-draft = 99`, and no main-model `n-gpu-layers`.

Benchmark (same prompt, temp 0, 300-token decode, warm second run; fresh ~1.04k
prompt for prefill). `accept` = `draft_n_accepted / draft_n`:

| variant | decode t/s | prefill t/s | accept | RSS | VRAM | gpu busy avg/max |
|---|---|---|---|---|---|---|
| CPU `llm-qwen` (router) | 9.13 | 17.4 | 0.697 | 117.7 GB | 0.05 GiB | 0/0% |
| `-ngl 99 -cmoe -nkvo` (router) | 2.01 | 44.7 | 0.708 | 95.6 GB | 7.30 GiB | 11/75% |
| `-ngl 99 -nkvo -ot ffn_.*_exps=CPU` | 2.01 | 63.6 | 0.708 | 97.4 GB | 7.30 GiB | 12/88% |
| `-ngl 20` | 5.04 | 14.6 | 0.734 | 56.3 GB | 7.94 GiB | 72/99% |
| `-ngl 8` | 5.89 | 14.4 | 0.746 | 79.7 GB | 7.97 GiB | 51/99% |
| `-ngl 40 -cmoe -nkvo` | 1.61 | 42.4 | 0.681 | 97.4 GB | 6.41 GiB | 14/89% |
| `n-gpu-layers-draft 99` (standalone) | 10.48 | 19.1 | 0.731 | 95.3 GB | 6.40 GiB | 10/96% |
| **`n-gpu-layers-draft 99` (router, final)** | **10.82** | 16.9 | 0.731 | 95.3 GB | 6.40 GiB | 12/99% |

The final variant: MTP acceptance 0.731, mean accepted length 4.55, VmRSS
95.3 GB (RssAnon 33.9 GB, RssFile 61.5 GB), `VmSwap` 0, 0 idle major faults,
no OOM.

## Follow-up notes

- **Prompt dependence.** The historical CPU figure is 11.18 t/s, from a different
  merge prompt with acceptance 0.858. This task's prompt gives 9.13 t/s on the
  same CPU config. The GPU win is measured against that same-prompt CPU run:
  **+18.5%** (10.82 vs 9.13). Against the historical 11.18 the final sits at
  parity (-3%); the same prompt would likely show the same +15-30% win.
- **Cosmetic Vulkan warning.** Every load prints
  `Failed to allocate pinned memory (Requested buffer size exceeds device buffer
  size limit: ErrorOutOfDeviceMemory)`. RADV refuses the pinned staging buffer;
  llama.cpp falls back to unpinned transfers. The model loads and runs.
- **Unused slot options.** The final config uses only `draftNGpuLayers` and
  `device`. `nGpuLayers`, `cpuMoe` and `noKvOffload` stay in the slot and den
  aspect as documented, tested knobs for a future model or a smaller context.
- **Left state.** brys is booted into `llm-qwen-gpu` and `llama-cpp` is active.
  The boot selection is one-shot; the default entry is unchanged.

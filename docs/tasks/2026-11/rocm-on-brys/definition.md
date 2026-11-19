---
type: Task
description: Diagnose why hsa_init fails on host brys with ROCm 7.2.4 while Vulkan works, and decide whether ROCm should be installed system-wide or per package.
status: open
authored_by: agent
timestamp: 2026-11-19T05:40:00+01:00
---

# ROCm on brys: the gfx803 card breaks `hsa_init`

## Result in one paragraph

ROCm is **not** broken and the kernel is **not** too old. The machine has a second, unsupported
GPU — an AMD Lexa (Polaris 12, `gfx803`, "Radeon RX 550") — and ROCm 7.2.4 refuses to start when
any node in the KFD topology reports a legacy doorbell type. The check is
`node_props.Capability.ui32.DoorbellType != 2` in `amd_gpu_agent.cpp`. It throws a **generic**
`HSA_STATUS_ERROR`, and `DiscoverGpu` only tolerates `HSA_STATUS_ERROR_INVALID_ISA`. So one old
card aborts `hsa_init()` for the whole machine, and every HIP consumer reports "no
ROCM-capable device". The R9700 is fully usable once that node is skipped: this was proved on the
live host by rewriting the node's `capability` word in-process, and again by making the node look
like a non-compute node. Decision: **do not install ROCm system-wide.** Build a patched ROCm per
package, and only when a HIP-only tool needs it; keep Vulkan for llama.cpp.

Related: [brys-kernel-7-zfs](../brys-kernel-7-zfs/definition.md) owns the kernel question and
states the ZFS block on a 7.x kernel. Read it, do not edit it from here.
[brys-r9700-model-fit](../brys-r9700-model-fit/definition.md) owns the model choice and the
Vulkan measurements.

## Symptom, as reported

| Probe                                                             | Result                                                                                                           |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `llama-cpp` with `rocmSupport = true` (ROCm 7.2.4)                | starts, then `ggml_cuda_init: failed to initialize ROCm: no ROCm-capable device is detected`                     |
| `rocminfo` (nixpkgs `rocmPackages.rocminfo` 7.2.4), user and root | `hsa api call failure at: .../rocminfo.cc:1329`, `Call returned HSA_STATUS_ERROR: A generic error has occurred.` |
| `rocm-smi`                                                        | lists both GPUs (it reads sysfs and `librrm`, not HSA)                                                           |
| Vulkan (`vulkaninfo`, llama.cpp Vulkan)                           | works                                                                                                            |

`rocminfo.cc:1329` is the `RET_IF_HSA_ERR(err)` line directly after `hsa_init()`. The failure is
inside `hsa_init()`, not in agent iteration. Source:
`projects/rocminfo/rocminfo.cc` in the ROCm 7.2.4 tree (see [Sources](#sources)).

## Root cause, with the evidence chain

1. **The kernel describes both GPUs correctly.** `/sys/class/kfd/kfd/topology/nodes/1` reports
   `gfx_target_version 120001`, 128 SIMDs, 64 CUs, a 34 208 743 424-byte VRAM bank and
   `capability 0x6873a280`. `nodes/2` reports `gfx_target_version 80003`
   (PCI id `1002:699f`, Polaris 12), `capability 0x00001280`.
2. **The `capability` word carries the doorbell type in bits 12–13.** The ABI is defined in
   `include/uapi/linux/kfd_sysfs.h`: `HSA_CAP_DOORBELL_TYPE_TOTALBITS_MASK 0x00003000`,
   `SHIFT 12`, values `PRE_1_0 0x0`, `1_0 0x1`, `2_0 0x2`. Decode of the two nodes:
   `(0x6873a280 >> 12) & 3 = 2` for the R9700, `(0x00001280 >> 12) & 3 = 1` for the Lexa.
3. **The kernel sets that value by ASIC family, not by kernel version.**
   `drivers/gpu/drm/amd/amdkfd/kfd_topology.c` sets `HSA_CAP_DOORBELL_TYPE_1_0` for
   `CHIP_POLARIS10/11/12` and `CHIP_FIJI`, and `HSA_CAP_DOORBELL_TYPE_2_0` for everything from
   gfx9 on. `kfd_device.c` hard-codes `doorbell_size = 8` for SOC15 and `4` for the older
   families. No kernel release can change this for a Polaris card.
4. **ROCr rejects the node and kills the whole runtime.**
   `projects/rocr-runtime/runtime/hsa-runtime/core/runtime/amd_gpu_agent.cpp:124`:

   ```cpp
   if (node_props.Capability.ui32.DoorbellType != 2)
     throw AMD::hsa_exception(HSA_STATUS_ERROR, "Agent creation failed.\nThe GPU node uses a deprecated doorbell type\n");
   ```

   `.../core/runtime/amd_topology.cpp:169-179` catches this in `DiscoverGpu`, but only skips the
   node when `e.error_code() == HSA_STATUS_ERROR_INVALID_ISA`. A generic `HSA_STATUS_ERROR` is
   rethrown, so `AMD::Load()` fails and `hsa_init()` returns "a generic error".

5. **The observed ioctl order matches that code path exactly.** An `LD_PRELOAD` shim over the KFD
   ioctls (script below) shows on brys: one `GET_CLOCK_COUNTERS` (node 1, the R9700), then
   nothing for node 2. The R9700's allocations all succeed. On the control host `oams` — same
   kernel, same nixpkgs pin, same ROCm 7.2.4 — there are two `GET_CLOCK_COUNTERS` and both GPUs
   are enumerated. The `GpuAgent` constructor calls the doorbell check _before_
   `GetClockCounters`, which is why the second call never happens.
6. **Proof, on the live host, without a rebuild.** A second `LD_PRELOAD` shim redirects reads of
   `nodes/2/properties` to a copy with only `capability` 4736 (`0x00001280`) changed to 8832
   (`0x00002280`, doorbell type 2). `rocminfo` then succeeds:

   ```
   Agent 2  Name: gfx1201  Marketing Name: AMD Radeon AI PRO R9700
            Uuid: GPU-2bb8e98891d4b3ff  Compute Unit: 64
            Size: 33406976 KB (31.9 GiB)
   Agent 3  Marketing Name: AMD Radeon RX 550 / 550 Series
   ```

   A third variant sets `simd_count 32` to `0` in the same copy, so `DiscoverGpu` skips the node
   for `NumFComputeCores == 0`. `hsa_init` succeeds and `rocminfo` lists **only** the CPU and the
   R9700. That is the state the fix should produce.

This is a known upstream defect: **ROCm/rocm-systems issue #8801**, "[Issue]: rocr-runtime — a
single pre-Vega GPU (DoorbellType != 2) aborts hsa_init() for ALL GPUs". It reports the same
`rocminfo` line and the same `gfx1200 + gfx803` combination. PR #4936 fixes it by throwing
`HSA_STATUS_ERROR_INVALID_ISA` and by widening the `DiscoverGpu` catch.

## Secondary defect: MMIO remap does not exist for pre-Vega cards

The shim also shows one failing ioctl on brys: `AMDKFD_IOC_ALLOC_MEMORY_OF_GPU`,
`gpu_id=53191` (node 2), `size=4096`, `flags=0x94000010` = `MMIO_REMAP | WRITABLE |
NO_SUBSTITUTE | COHERENT` → `-ENOMEM`. libhsakmt allocates that page for every GPU in
`fmm.c:map_mmio()`.

The kernel refuses it because `adev->rmmio_remap.bus_addr == 0`:
`kfd_chardev.c` returns `-ENOMEM` when that field is zero. The field is only ever written by
`set_reg_remap()` in `nbio_v6_1.c`, `nbio_v7_*.c`, `nbif_v6_3_1.c`, and by `nv.c`, `soc15.c`,
`soc21.c`, `soc24.c` during init. `vi.c` — the pre-SOC15 (Polaris/Tonga/Fiji) path — never calls
it, and `grep` finds no `rmmio` reference in that file at all.

This is **not** fatal: `map_mmio()` failure only prints `pr_err` and leaves
`mmio_aperture.base == NULL`. It matters for two reasons: it is a second, silent sign that the
card cannot work with ROCm 7, and it is the only GPU-related `-ENOMEM` in the trace, which makes
it a plausible false lead.

## Why the kernel is not the cause (owner hypothesis, tested)

The hypothesis was: kernel 6.18.62 is too old for ROCm 7.2.4 and `gfx1201`. Result: **rejected as
the cause of this failure.**

| Test                                              | Evidence                                                                                                                                                                                                                                                                   |
| ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Same kernel, same ROCm, supported GPUs            | `oams` runs 6.18.62 and the same nixpkgs pin; `rocminfo` 7.2.4 works there and enumerates `gfx1031` and `gfx90c`.                                                                                                                                                          |
| KFD ABI version                                   | `AMDKFD_IOC_GET_VERSION` returns **1.18** on brys _and_ on oams. ROCm 7.2.4 accepts 1.18 and does not ask for more.                                                                                                                                                        |
| Unknown ioctls                                    | The shim logged 21 KFD ioctls on brys (`GET_VERSION`, `ACQUIRE_VM`, `SET_MEMORY_POLICY`, `ALLOC_MEMORY_OF_GPU`, `MAP_MEMORY_TO_GPU`, `SET_XNACK_MODE`, `GET_CLOCK_COUNTERS`). None returned `ENOTTY`/`EINVAL`. The 6.18 kernel understands every call the runtime makes.   |
| `gfx1201` driver support                          | KFD created the node, 138 cache objects, 2 SDMA engines, a 34 GB VRAM bank, `num_xcc 1`, `unique_id`; `amdgpu` loaded `gfx_v12_0`, `mes_v12_0`, `sdma_v7_0`. Boot log: `kfd kfd: amdgpu: added device 1002:7551`.                                                          |
| gfx12 kernel-side features                        | The KFD properties include `capability2`, `debug_prop`, `num_xcc`, `unique_id`, i.e. the newer topology fields are present. A runtime built for an older ABI would see zeros here, not an error.                                                                           |
| Cause of the abort                                | It is a userspace `if` on a bit the kernel sets per ASIC family. It fires for the Lexa, never for the R9700.                                                                                                                                                               |
| AMD validation matrix                             | ROCm 7.2.1 lists Ubuntu 24.04.4 HWE (kernel **6.17**), Ubuntu 22.04 (6.8) and RHEL 10.1 (6.12). 6.18 is outside that set, so the host is unvalidated, but Phoronix ran ROCm 7.0.0 and 7.2.3 on an R9700 with stock **6.17** drivers, so a 6.1x kernel is enough for RDNA4. |
| A newer kernel is also expensive and useless here | [brys-kernel-7-zfs](../brys-kernel-7-zfs/definition.md) shows that the only 7.x in nixpkgs is 7.3, that no released OpenZFS supports it, and that brys boots from ZFS. Even with a 7.x kernel, `kfd_device.c` would still report doorbell type 1 for the Polaris card.     |

What remains true: a 6.18 kernel is not in AMD's support matrix. Treat that as a **support gap to
re-check at the next ROCm or kernel move**, not as the fault to chase now.

## Diagnostics that were run

All probes are read-only. The card stayed with the other session; no model was loaded, no
benchmark was run, no host configuration was changed, no `nixos-rebuild` was called.

| #   | Probe                                          | Result on brys                                                                                                                                                                              |
| --- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `rocminfo` 7.2.4, plain                        | `HSA_STATUS_ERROR` at `rocminfo.cc:1329`                                                                                                                                                    |
| 2   | `AMD_LOG_LEVEL=7`                              | no extra output (release build compiles `pr_debug` out)                                                                                                                                     |
| 3   | `HSA_ENABLE_DEBUG=1`                           | no extra output (`ifdebug` is compile-time)                                                                                                                                                 |
| 4   | `ROCR_VISIBLE_DEVICES=0`                       | unchanged: libhsakmt maps every node before the filter applies                                                                                                                              |
| 5   | `HSA_ENABLE_SDMA=0`                            | unchanged                                                                                                                                                                                   |
| 6   | as root (`sudo -n`)                            | unchanged; `/dev/kfd` is `crw-rw-rw-`, `id` shows no `render` group but the device does not need it                                                                                         |
| 7   | VRAM at test time                              | 21.2 GiB used of 34.2 GiB while the other session's model was loaded, and **74.7 MiB used** with the card idle — the failure is the same in both cases, so `-ENOMEM` is not VRAM exhaustion |
| 8   | `strace -f -e trace=openat,ioctl`              | `/dev/kfd` opens, all sysfs reads succeed, one `ALLOC_MEMORY_OF_GPU` returns `ENOMEM`                                                                                                       |
| 9   | `kfdspy.so` ioctl shim                         | failing alloc is `gpu_id=53191` (node 2, gfx803), 4096 B, `MMIO_REMAP`                                                                                                                      |
| 10  | Same shim on `oams`                            | all allocations succeed; two `GET_CLOCK_COUNTERS`                                                                                                                                           |
| 11  | Shim + rewritten `capability` (doorbell 1 → 2) | `hsa_init` succeeds; R9700 and RX 550 enumerated                                                                                                                                            |
| 12  | Shim + `simd_count 0` on node 2                | `hsa_init` succeeds; only the R9700 is enumerated                                                                                                                                           |
| 13  | `journalctl -k`                                | `added device 1002:7551` and `1002:699f`; no KFD error                                                                                                                                      |

## System-wide or per package

`hardware.graphics.extraPackages` builds one `buildEnv` and symlinks it at `/run/opengl-driver`
(`nixos/modules/hardware/graphics.nix`). There is **no `hardware.amdgpu` module** in this nixpkgs
pin: `ls nixos/modules/hardware/ | grep -i amd` is empty, so `hardware.amdgpu.opencl` from the
brief does not exist. The documented route for ROCm is
`hardware.graphics.extraPackages = [ rocmPackages.clr rocmPackages.clr.icd ]`.

| Criterion                         | System-wide (`hardware.graphics.extraPackages`)                                                                                                                                                                           | Per package (override on the consumer)                                                             |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| What lands where                  | ROCm libs and the OpenCL ICD in `/run/opengl-driver`, on the default `LD_LIBRARY_PATH` of every process                                                                                                                   | only inside that derivation's closure; nothing global                                              |
| Measured size                     | `rocmPackages.rocm-runtime` closure **790.9 MB** (the ROCm LLVM toolchain is 760 MB of it); `rocminfo` closure 791.0 MB; `rocmPackages.clr` added 5 paths, 90.56 MiB unpacked, on top of the shared paths already present | same closure, but carried once per consuming package; several HIP consumers duplicate it           |
| Version coupling                  | one ROCm version for the whole system, chosen at rebuild time; a kernel or Mesa change must stay compatible for all users                                                                                                 | each consumer pins its own ROCm, e.g. a patched runtime for llama.cpp next to a stock one for vLLM |
| Effect of the gfx803 bug          | if the local ROCm is patched, every HIP program benefits; if not, every HIP program fails the same way                                                                                                                    | the patch is scoped to the package that needs it                                                   |
| Blast radius of a bad build       | system-wide: a broken `libamdhip64` or a wrong `LD_LIBRARY_PATH` entry can change what unrelated programs load                                                                                                            | one package                                                                                        |
| Maintenance                       | one override, one rebuild                                                                                                                                                                                                 | one override per consumer; drift between them                                                      |
| NixOS rebuild needed to change it | yes                                                                                                                                                                                                                       | no, a `nix build` is enough                                                                        |

**Recommendation: per package.** The deciding factors are the patched runtime (the fix is a
ROCm-internal source change, and it must not silently change behaviour for every HIP program on
the host) and the fact that llama.cpp — the only current consumer — does not gain from HIP on
this card (next section).

## What ROCm would buy, and what it costs

| Gain                          | Status on `gfx1201`                                                                                                                                                                                                                          | Worth it?                                                                       |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| llama.cpp HIP decode          | Community scoreboards put the R9700 at **138.8 t/s Vulkan** vs **98.0 t/s ROCm** (Llama 2 7B Q4_0, tg128, FA); prefill 5620 vs 4773. An RX 9060 XT (`gfx1200`) run shows Vulkan +1.6 %/+8.8 % decode and a prefill tie.                      | No. Vulkan is already the faster path for the models in `brys-r9700-model-fit`. |
| llama.cpp HIP prefill         | Mixed: one RX 9070 XT report shows HIP 4199 vs Vulkan 2866 t/s at pp512 on 8B, the R9700 scoreboard shows the opposite.                                                                                                                      | Only for a prefill-bound workload, and only after a measurement.                |
| vLLM, SGLang, PyTorch, Triton | HIP only. `gfx1201` is not in the published wheels (they target `gfx942`), so vLLM must be built from source with `PYTORCH_ROCM_ARCH=gfx1201`; known gaps exist (e.g. FP8 platform detection).                                               | Yes, when a HIP-only tool is actually needed.                                   |
| OpenCL (`clr.icd`)            | Not used by anything in this tree today.                                                                                                                                                                                                     | No.                                                                             |
| Cost                          | ~0.8 GB closure for the runtime alone, a multi-GB stack once math libraries are added (not measured here); the patched runtime must be carried until nixpkgs ships the upstream fix; the kernel must keep a KFD ABI the chosen ROCm accepts. | Acceptable only per package.                                                    |

## Decision tree

1. **`rocminfo` succeeds?** Nothing to do. Record the ROCm and kernel versions.
2. **`rocminfo` fails and any node shows `(capability >> 12) & 3 != 2`?** That node is the cause.
   Do not touch the kernel, the IOMMU, `amdgpu.noretry` or the group setup.
   - Preferred: make ROCr skip the node. Patch `rocm-runtime` so the deprecated doorbell throws
     `HSA_STATUS_ERROR_INVALID_ISA` (upstream PR #4936). One source line, proven to work.
   - Alternative, if the card is unused: remove it, or keep it out of `amdgpu`. Then stock ROCm
     7.2.4 needs no patch.
3. **The patched runtime works (case proven here)?** Wire it **per package**, never system-wide:
   `rocmPackages.rocm-runtime.overrideAttrs` with the patch, then
   `llama-cpp.override { rocmSupport = true; rocmPackages = patched; }`, or the same runtime for
   a `vllm` build.
4. **Measure before adopting.** Build the HIP llama.cpp, run one model from
   [brys-r9700-model-fit](../brys-r9700-model-fit/definition.md) at the same quantisation and
   context as its Vulkan row, and compare decode and prefill. Keep Vulkan unless HIP wins, or
   unless a HIP-only tool needs the runtime anyway.
5. **`hsa_init` fails with no bad doorbell node?** Then go back to the general candidates:
   `ENOTTY`/`EINVAL` ioctls (kernel/ROCm ABI), `amdgpu_vm_validate` errors in the kernel log,
   VRAM pressure, IOMMU. The diagnostic script below prints all of them.
6. **A later nixpkgs carries ROCm with PR #4936?** Drop the patch, re-run the script, keep the
   rest of the decision.

## Diagnostic script

Save as `rocm-diag.sh` and run it on the host. It is read-only: it reads sysfs, runs `rocminfo`
if present, and greps the kernel log. It prints the doorbell type, which is the single most
useful number here.

```bash
#!/usr/bin/env bash
# rocm-diag.sh - read-only ROCm/HSA diagnosis for a KFD host.
# Usage: ./rocm-diag.sh [path-to-rocminfo]
set -u
ROCK="${1:-rocminfo}"

echo "== host =="
uname -srm; cat /etc/os-release 2>/dev/null | grep -E '^(NAME|VERSION)=' || true
echo "page_size=$(getconf PAGE_SIZE)"
id

echo
echo "== kernel command line =="
cat /proc/cmdline

echo
echo "== KFD nodes: doorbell type and identity =="
# DoorbellType lives in bits 12..13 of the node capability word.
# 0 = pre-1.0, 1 = 1.0 (pre-Vega), 2 = 2.0 (Vega and later).
python3 - <<'PY'
import glob, os
for props in sorted(glob.glob('/sys/class/kfd/kfd/topology/nodes/*/properties')):
    node = props.split('/')[-2]
    d = {}
    for line in open(props):
        k, _, v = line.partition(' ')
        d[k] = v.strip()
    try:
        cap = int(d.get('capability', '0'))
    except ValueError:
        cap = 0
    db = (cap >> 12) & 3
    gfx = int(d.get('gfx_target_version', '0'))
    # Node 0 is the CPU node: gfx_target_version 0, no compute cores. Skip it.
    is_gpu = gfx != 0 and (d.get('simd_count', '0') != '0')
    flag = '  <-- ROCr 7.x aborts on this' if (is_gpu and db != 2) else ''
    print(f"node {node}: gfx_target_version={gfx} capability=0x{cap:08x} "
          f"DoorbellType={db}{flag}")
    print(f"          simd_count={d.get('simd_count')} "
          f"device_id={d.get('device_id')} hive_id={d.get('hive_id')} "
          f"sdma={d.get('num_sdma_engines')}")
PY

echo
echo "== memory pressure (a failed alloc can be plain VRAM exhaustion) =="
for c in /sys/class/drm/card*/device; do
  [ -r "$c/mem_info_vram_used" ] || continue
  echo "$(basename "$(dirname "$c")"): vram_used=$(cat "$c/mem_info_vram_used") \
vram_total=$(cat "$c/mem_info_vram_total") gtt_used=$(cat "$c/mem_info_gtt_used")"
done

echo
echo "== rocminfo =="
if command -v "$ROCK" >/dev/null 2>&1 || [ -x "$ROCK" ]; then
  "$ROCK" 2>&1 | grep -E 'ROCk|hsa api|Call returned|Agent [0-9]|Name:|Marketing Name|gfx' | head -40
  echo "rocminfo exit=$?"
else
  echo "rocminfo not found; pass its path as the first argument"
fi

echo
echo "== kernel log: KFD and amdgpu =="
journalctl -k -b --no-pager 2>/dev/null \
  | grep -iE 'kfd|amdgpu' \
  | grep -viE 'command submission' \
  | tail -25 || echo "journal unavailable (needs root or a persistent journal)"

echo
echo "== verdict =="
echo "Any node with DoorbellType != 2 aborts hsa_init() in ROCm 7.x."
echo "Fix: skip that node in ROCr (upstream PR #4936); do not change the kernel."
```

To confirm the cause without rebuilding ROCm, add the `LD_PRELOAD` shim from this task: copy
`nodes/<N>/properties`, set `capability = (cap & ~0x3000) | 0x2000` (or set `simd_count 0`), and
interpose `fopen`/`open`/`openat` to serve the copy. If `rocminfo` then succeeds, the node is the
cause.

## Acceptance test

1. `rocminfo` on brys prints `gfx1201` and `hipGetDeviceCount` returns 1 from a small HIP probe.
   No change to boot parameters, groups, IOMMU or the kernel.
2. The fix lives in exactly one place: one `rocm-runtime` patch plus one consumer override.
   `nix build` alone reproduces it; no `nixos-rebuild` is needed to change ROCm.
3. One model from `brys-r9700-model-fit` runs under llama.cpp HIP at the same quantisation and
   context as its Vulkan row, with decode and prefill recorded next to the Vulkan number. If HIP
   loses, the task keeps Vulkan and says so.
4. `git log`/`jj log` shows no system-wide ROCm package and no kernel change from this task.

## Risks and open questions

- **The Lexa stays in the machine.** The patch is required on every ROCm upgrade until nixpkgs
  carries the upstream fix. If the card is ever removed, the stock runtime is enough.
- **The patch changes a guard, not a driver.** Skipping the node is safe for us; relaxing the
  check (allowing doorbell type 1) is _not_ recommended, because that card cannot run ROCm 7
  queues correctly and would enter the agent list.
- **`gfx1201` is officially supported**, but the host runs outside AMD's OS matrix (kernel 6.18).
  Re-check the matrix at the next ROCm move.
- **vLLM on `gfx1201` is a source build** with known gaps; it is a separate decision, not a
  side effect of this task.
- **Closure sizes were measured for the runtime only.** A full ROCm math stack was not built
  here; budget several GB if vLLM/PyTorch lands.
- **PCIe Gen4 x8** limits prefill more than decode. A HIP prefill win may not reproduce on this
  slot.

## Sources

Host and nixpkgs facts:

- `nix flake metadata` → nixpkgs `26.11.20261106.296d5fa`; `nix eval nixpkgs#linux.version` →
  `6.18.62`; `nix eval nixpkgs#rocmPackages.rocm-runtime.version` → `7.2.4`.
- Live sysfs on brys: `/sys/class/kfd/kfd/topology/nodes/{1,2}/properties`,
  `/sys/class/drm/card{1,2}/device/mem_info_*`, `/proc/cmdline`, `journalctl -k -b`.
- Measured closures: `nix path-info -ShS` on `rocm-runtime-7.2.4` (790.9 MB) and
  `rocminfo-7.2.4` (791.0 MB); `nix build --dry-run nixpkgs#rocmPackages.clr` (5 paths,
  90.56 MiB unpacked).

ROCm 7.2.4 source (nixpkgs `rocmPackages.rocm-runtime.src`, store path
`/nix/store/7xisf6zpx6xrfzrwyz180izg5dcsbpq5-source`):

- `projects/rocr-runtime/runtime/hsa-runtime/core/runtime/amd_gpu_agent.cpp:124` — the
  `DoorbellType != 2` throw.
- `projects/rocr-runtime/runtime/hsa-runtime/core/runtime/amd_topology.cpp:169-179` —
  `DiscoverGpu` skips only `HSA_STATUS_ERROR_INVALID_ISA`.
- `projects/rocr-runtime/runtime/hsa-runtime/core/runtime/runtime.cpp:121, 2371` — `Acquire()`,
  `Load()`; `hsa_ext_amd.cpp:154` — `handleException()` returns `HSA_STATUS_ERROR` for a rethrown
  `hsa_exception`.
- `projects/rocr-runtime/libhsakmt/src/fmm.c:2637-2690` — `map_mmio()` allocates
  `MMIO_REMAP|WRITABLE|COHERENT`; `fmm.c:3112-3126` — a failure only prints `pr_err`.
- `projects/rocminfo/rocminfo.cc:1329` — the reported failure line is the check after
  `hsa_init()`.

Linux 6.18.62 source (store path `/nix/store/p2r74pw41iknpvffsc49srvsc28vf4cj-linux-6.18.62.tar.xz`):

- `include/uapi/linux/kfd_sysfs.h:38-43` — doorbell type mask, shift and values.
- `drivers/gpu/drm/amd/amdkfd/kfd_topology.c:2129-2148` — `CHIP_POLARIS12` gets type `1_0`,
  everything gfx9+ gets `2_0`.
- `drivers/gpu/drm/amd/amdkfd/kfd_device.c:212-251` — `doorbell_size` 8 for SOC15, 4 otherwise.
- `drivers/gpu/drm/amd/amdkfd/kfd_chardev.c` (`kfd_ioctl_alloc_memory_of_gpu`) — `-ENOMEM` when
  `rmmio_remap.bus_addr` is zero; no log line.
- `drivers/gpu/drm/amd/amdgpu/vi.c` — no `rmmio` reference; `set_reg_remap` is called only from
  `nv.c`, `soc15.c`, `soc21.c`, `soc24.c`.
- `drivers/gpu/drm/amd/amdgpu/amdgpu_amdkfd_gpuvm.c:150-265` — the KFD memory limits that were
  checked and excluded (`ttm` 67.5 GB, system 15/16 RAM).

Upstream and vendor sources:

- ROCm/rocm-systems issue **#8801**, "a single pre-Vega GPU (DoorbellType != 2) aborts hsa_init()
  for ALL GPUs" — <https://github.com/ROCm/rocm-systems/issues/8801>; fix in PR #4936.
- AMD, _System requirements (Linux)_, ROCm 7.2.x — supported GPU list (Radeon AI PRO R9700,
  `gfx1201`) — <https://rocm.docs.amd.com/projects/install-on-linux/en/docs-7.2.3/reference/system-requirements.html>
- AMD, _Linux support matrices by ROCm version_ (ROCm 7.2.1: Ubuntu kernel 6.17 HWE, 6.8;
  RHEL 6.12) —
  <https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/compatibility/compatibilityrad/native_linux/native_linux_compatibility.html>
- Phoronix, _ROCm 7.0.0 vs. ROCm 7.2.3 Performance On The AMD Radeon AI PRO R9700_ (stock 6.17
  kernel drivers) — <https://www.phoronix.com/review/amd-rocm7-723>
- llama.cpp discussion #15021, _Performance of llama.cpp on AMD ROCm (HIP)_ (gfx1201 Vulkan vs
  HIP) — <https://github.com/ggml-org/llama.cpp/discussions/15021>
- RDNA4 scoreboard summary with R9700 rows (Vulkan 138.8 / ROCm 98.0 tg128; 5620 / 4773 pp512) —
  <https://runaihome.com/blog/rdna4-vulkan-vs-rocm-local-llm-benchmark-2026/>
- RX 9060 XT (`gfx1200`) Vulkan vs ROCm matrix — <https://github.com/parsapp/rx9060xt-llm-benchmarks>
- vLLM on `gfx1201` requires a source build with `PYTORCH_ROCM_ARCH=gfx1201` —
  <https://gist.github.com/dobriak/9dff293e5ea6ffc9f4258bf52c3b5333>
- `polaris-revival` notes: `gfx803` is DoorbellType 1 / 32-bit MMIO doorbells, rejected by ROCm
  7.x — <https://github.com/Rta-Forge/polaris-revival/blob/main/docs/GFX803_PORTING_NOTES.md>

## Related

- [brys-kernel-7-zfs](../brys-kernel-7-zfs/definition.md) — why a 7.x kernel is blocked on this
  host, and why it would not help here.
- [brys-r9700-model-fit](../brys-r9700-model-fit/definition.md) — the models and the Vulkan
  measurements to compare a HIP run against.
- `docs/local-llms.md` — the measured model table (owned by another task; not edited here).

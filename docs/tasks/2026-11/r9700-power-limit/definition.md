---
type: Task
description: Cap the 300 W board power of the Radeon AI PRO R9700 on brys to cut heat and wall power, after measuring what each cap costs in llama.cpp decode and prefill.
status: open
authored_by: agent
timestamp: 2026-11-19T06:00:00+01:00
---

# Cap the R9700 board power on brys

## Context

- **The card.** One AMD Radeon AI PRO R9700 on host `brys`: Navi 48, `gfx1201` (GC 12.0.1),
  32 GB (31.86 GiB), 640 GB/s, PCIe `1002:7551` at PCI address `0d:00.0`. Board power limit
  300 W from the factory.
- **The workload.** llama.cpp on Vulkan serves every local model (`llama-swap` on port 39700).
  Throughput for each model is measured in
  [brys-r9700-model-fit](../brys-r9700-model-fit/measurements.md).
- **The goal.** The owner wants the option to run the card at 200–300 W, possibly lower, to cut
  heat, fan noise and wall power. The first benchmark runs must record the **full-throttle
  baseline at 300 W first**, so the control mechanisms are prepared now and applied later.
- **The constraint that shapes this task.** Nobody has written `power1_cap` on this card yet.
  A write is unverified until someone does it and reads the value back. This task therefore
  delivers research, a measurement plan and a tool. **It changes no value.**

## What brys exposes today

Read-only probe, 2026-11-19, kernel `6.18.62`, driver `amdgpu`, hwmon node
`/sys/class/drm/card1/device/hwmon/hwmon2`. Nothing was written.

| file                                          | value                                | note                                          |
| --------------------------------------------- | ------------------------------------ | --------------------------------------------- |
| `power1_cap`                                  | `300000000` = **300 W**              | mode `-rw-r--r--`, so root can write it       |
| `power1_cap_min`                              | `210000000` = **210 W**              | the reachable floor, see below                |
| `power1_cap_max`                              | `300000000` = **300 W**              | equals the default                            |
| `power1_cap_default`                          | `300000000` = **300 W**              | the factory value                             |
| `power1_label`                                | `PPT`                                | the cap is the board input power              |
| `power1_average`                              | 1–8 W at idle                        | the only live power file on this card         |
| `power1_input`                                | **absent**                           | this ASIC has no instantaneous power sensor   |
| `power2_*` (fastPPT)                          | **absent**                           | only the sustained PPT0 limit exists          |
| `temp1_input` / `temp2_input` / `temp3_input` | 36 / 37 / 34 °C                      | edge / junction / memory, idle                |
| `fan1_input`                                  | ~1296 rpm                            | idle                                          |
| `power_dpm_force_performance_level`           | `auto`                               | writable by root                              |
| `power_dpm_state`                             | `performance`                        | legacy interface, it does nothing on this GPU |
| `pp_od_clk_voltage`                           | **absent**                           | overdrive is off                              |
| `pp_power_profile_mode`                       | 8 profiles, `BOOTUP_DEFAULT*` active | writable                                      |
| `gpu_metrics`                                 | present                              | binary SMU counter block                      |
| `pp_dpm_sclk` / `pp_dpm_mclk`                 | 500/0*/2350 MHz, 96…1258 MHz         | idle state                                    |

Other facts from the same probe:

- `ppfeaturemask = 0xfff7bfff` is the **kernel default** of Linux 6.18, not a local setting.
  There is no `amdgpu.*` option on the kernel command line and no `amdgpu` line in
  `/etc/modprobe.d/`.
- Two AMD GPUs are on the box: the R9700 (`card1`, `0d:00.0`) and a Radeon 540
  (`card2`, `0e:00.0`). **Never select the card by number**; select it by PCI id.
- `rocm-smi`, `amdgpu_top` and `lact` are **not installed** on brys. `llama-bench`,
  `llama-server` and `llama-cli` are on PATH. User `kdn` has `NOPASSWD: ALL` on brys.

## Kernel interfaces

| interface                           | what it does                                                                                                           | writable | on brys | needs the overdrive bit                 |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | -------- | ------- | --------------------------------------- |
| `hwmon/power1_cap`                  | board power limit (PPT), in microwatt                                                                                  | root     | **yes** | **no**                                  |
| `hwmon/power1_cap_min`              | lowest accepted cap                                                                                                    | no       | yes     | no                                      |
| `hwmon/power1_cap_max`              | highest accepted cap                                                                                                   | no       | yes     | no (the cap rises when overdrive is on) |
| `hwmon/power1_cap_default`          | factory cap                                                                                                            | no       | yes     | no                                      |
| `hwmon/power1_average`              | SMU moving average of board input power                                                                                | no       | yes     | no                                      |
| `hwmon/power1_input`                | instantaneous board power                                                                                              | no       | **no**  | no                                      |
| `power_dpm_force_performance_level` | force `auto`/`low`/`high`/`manual`/`profile_*`                                                                         | root     | yes     | `manual` needs it                       |
| `power_dpm_state`                   | legacy `battery`/`balanced`/`performance`                                                                              | root     | yes     | no, and it does nothing on this GPU     |
| `pp_od_clk_voltage`                 | per‑power‑level clock and voltage edit; one file, command letters `s`/`m`/`p`/`vc`/`vo`, `r` to restore, `c` to commit | root     | **no**  | **yes**                                 |
| `gpu_metrics`                       | binary SMU metrics block                                                                                               | no       | yes     | no                                      |
| `pp_power_profile_mode`             | SMU activity‑monitor profile, not the PPT                                                                              | root     | yes     | a `CUSTOM` profile needs `manual`       |

Two source facts matter for the "needs the overdrive bit" column:

- `power1_cap` is declared as `S_IRUGO | S_IWUSR` and its visibility test in
  `amdgpu_pm.c` checks only the ASIC family and the APU flag. It **never** tests
  `PP_OVERDRIVE_MASK`. A power cap therefore needs no kernel parameter.
- `pp_od_clk_voltage` is gated on `amdgpu_dpm_is_overdrive_supported()`, which returns
  `smu->od_enabled`. `smu_set_funcs()` sets `od_enabled` when `adev->pm.pp_feature` carries
  `PP_OVERDRIVE_MASK`, which is bit 14 (`0x4000`) of `ppfeaturemask`.
- The commit is **not** a second file. It is a write of `c` to the same `pp_od_clk_voltage`
  file, which dispatches `AMD_PP_TASK_READJUST_POWER_STATE`. That file has no command for the
  power limit — the PPT is not reachable there.

## Why the range is 210–300 W

The values are computed, not hard-coded. The card reports the `smu_v14_0` IP block, and only the
`smu_v14_0_2` table produces these four numbers — the `smu_v14_0_0` table has no power-limit
callbacks at all, and a missing callback makes `power1_cap_min` read as an empty line, not as
210 W. `smu_v14_0_2_get_power_limit()` does this:

```c
msg_limit       = pptable->SkuTable.MsgLimits.Power[PPT_THROTTLER_PPT0][POWER_SOURCE_AC];
max_power_limit = msg_limit * (100 + od_percent_upper) / 100;
min_power_limit = power_limit * (100 + od_percent_lower) / 100;
```

- `msg_limit` is 300 W on this VBIOS (`113-EXT120418-102`).
- `OverDriveLimitsBasicMin.Ppt` is −30 %, so the floor is 300 × 0.70 = **210 W**.
- Overdrive is off, so `od_percent_upper` is 0 and the ceiling stays at 300 W.

The driver reads those four numbers **once**, during `smu_hw_init()`, and caches them in
`smu->min_power_limit` / `max_power_limit`. Two consequences:

1. `smu_set_power_limit()` rejects a value outside the cached range with `-EINVAL` before any
   message reaches the SMU. The floor is a hard wall in userspace.
2. The floor does not move when the cap moves. There is **no ratchet**: you cannot step 300 → 250
   → 175 W. 200, 175 and 150 W are **not reachable** on this card and kernel.

The write path is `smu_v14_0_2_set_power_limit()` → `smu_v14_0_set_power_limit()` →
`SMU_MSG_SetPptLimit`, which also fails with `-EOPNOTSUPP` when the SMU feature `PPT_BIT` is
off. The attribute mode itself is unconditional, so the value does reach the SMU. A value the
SMU refuses comes back as an error; a value the driver clamps shows up as an unchanged
read-back. That is exactly why a write must always be verified by a read-back.

## Overdrive is the wrong lever here

`hardware.amdgpu.overdrive.enable = true` (or `amdgpu.ppfeaturemask=0xfff7ffff`) sets bit 14.
That does three things:

- it exposes `pp_od_clk_voltage`;
- it raises **`power1_cap_max` above 300 W**, because `od_percent_upper` becomes the pptable's
  positive limit;
- it does **not** lower the 210 W floor, because the floor uses `od_percent_lower`, which is
  read whether or not overdrive is on.

So overdrive buys headroom above 300 W and a way to overclock. It buys nothing below 210 W.
Do not enable it to save power. If a cap below 210 W is required later, the only path is a
modified `pp_table` (the PPTABLE blob), which is out of scope here.

## Vendor tools

None of them is installed on brys today. All three read and write the same sysfs files, so all
three hit the same 210 W floor.

| tool         | in nixpkgs                                                          | needs ROCm compute | headless                          | what it gives                                                                    |
| ------------ | ------------------------------------------------------------------- | ------------------ | --------------------------------- | -------------------------------------------------------------------------------- |
| `rocm-smi`   | yes, `pkgs/development/rocm-modules/rocm-smi` 7.2.4                 | **no**             | yes                               | `--showpower`, `--showtemp`, `--setpoweroverdrive <W>`, `--resetpoweroverdrive`  |
| `amdgpu_top` | yes, `pkgs/by-name/am/amdgpu_top` 0.11.5                            | **no**             | yes                               | TUI, `-d`, `-J/--json` from `gpu_metrics`; **monitor only, it cannot set a cap** |
| `lact`       | yes, `pkgs/by-name/la/lact` 0.10.1, module `services.hardware.lact` | **no**             | yes, through `lactd` + `lact cli` | `lact cli power-limit get` / `set <W>`, plus a GUI                               |

- `rocm-smi` propagates **only `libdrm`** in nixpkgs. It talks to the kernel over DRM ioctls and
  sysfs. A broken `hsa_init` on brys does not affect it, because it never loads the HIP runtime.
  Its `--setpoweroverdrive` calls `rsmi_dev_power_cap_set()`, which writes `power1_cap` and
  pre-checks `power1_cap_min`/`max` — it refuses 200 W with "Value cannot be less than: 210W".
- `amdgpu_top` decodes `gpu_metrics` with `libdrm` and nothing else. It reports power, clocks and
  temperatures well, and it is the best sampler during a benchmark. It cannot change a value.
- `lact` links `libOpenCL.so` and `libvulkan.so` from `ocl-icd` and `vulkan-loader`. That is the
  ICD loader and the loader, not a working compute stack, so the daemon starts and the power path
  works even when `hsa_init` fails. Its OpenCL/Vulkan info panes may stay empty. LACT writes
  `power1_cap` too, so its GUI slider shows the same 210–300 W range.

The helper in this task uses **plain sysfs** and no extra package, so it works today without a
rebuild of brys.

## What a decode actually costs in power

- **Decode runs at batch 1.** Each token reads every activated weight once. The R9700 has
  640 GB/s and holds a 27B dense model at about 30 t/s, so the memory system, not the shader
  array, sets the pace. The SMU can drop SCLK and still feed the memory controllers.
- **Prefill is matrix-matrix work.** `pp512` fills the shader array and pulls close to the board
  limit. Prefill, and therefore time-to-first-token at long context, is the phase a cap taxes
  first.
- **Hypothesis to test:** a cap between 210 and 300 W costs little decode rate and visible
  prefill rate. The sweep must show where the knee is, not assume it.
- **The served preset is a special case.** `Qwen3.8-Flash-Next UD-IQ1_S` at `--n-cpu-moe 26`
  streams expert tensors from host RAM over PCIe x8. Its decode power is a mix of GPU, PCIe,
  CPU package and DDR4. A GPU cap can even free PSU headroom for the CPU. Measure it in its own
  table and never mix it with the fully-resident rows.

## Measurement plan

Run this after the 300 W baseline exists. One person, one terminal for the benchmark, one for
the sampler. Each point takes about 3 minutes.

**Fixed model and flags.** Model `surveyed/qwen3.8-27b.gguf` (16.46 GB, dense 27B, fully
resident in 32 GB). Same flags as [brys-r9700-model-fit](../brys-r9700-model-fit/measurements.md):

```sh
MESA_VK_DEVICE_SELECT=1002:7551! llama-bench \
  -m /var/lib/kdn/llms/models/surveyed/qwen3.8-27b.gguf \
  -ngl 99 -fa on -p 512 -n 128 -r 3
```

`-p 512` is the prefill figure, `-n 128` is the decode figure, `-r 3` gives three repeats.

**Per cap level:**

1. **Quiesce the box.** No resident `llama-server`, `mem_info_vram_used` near zero, load average
   below 1, `power_dpm_force_performance_level` at `auto`. A forgotten server lowers decode rate
   and confuses the whole table.
2. **Set the cap** and confirm the read-back:
   `./hack/r9700-power.sh --host brys set <watt> --apply`
3. **Idle soak 60 s**, then record idle power, temperatures and fan:
   `./hack/r9700-power.sh --host brys show --sample 30`
4. **Bench.** Run `llama-bench`. While the decode phase runs, start
   `./hack/r9700-power.sh --host brys show --sample 30` in the second terminal and keep the mean
   and the max. Repeat if the two runs disagree by more than 5 %.
5. **Record** cap, decode t/s, prefill t/s, power mean, junction temperature, fan rpm, and
   `t/s per W`.
6. **Wall power, if a wall meter is on the box.** Note it by hand next to the row. The host has
   no PDU and no smart plug yet (that is
   [brys-power-draw-zigbee](../../2026-10/brys-power-draw-zigbee/definition.md)).

**Order of the sweep.** 300 → 275 → 250 → 225 → 210 → **300 again**. The final repeat is a drift
check: if it does not match the first 300 W row, the room or the card warmed up and the whole
table needs a re-run. The first 300 W row is the baseline, and it is taken with **no write at
all** — that is the number the card already gives today.

If step 2 fails its read-back, **stop**. A failed read-back means this kernel and VBIOS do not
accept the cap, and every later row would describe a card that never changed.

**Fill this table.** Six rows, one per cap.

|        cap W | decode t/s | prefill t/s | power mean W | junction °C | fan rpm | t/s per W | wall W (manual) |
| -----------: | ---------: | ----------: | -----------: | ----------: | ------: | --------: | --------------: |
|          300 |            |             |              |             |         |           |                 |
|          275 |            |             |              |             |         |           |                 |
|          250 |            |             |              |             |         |           |                 |
|          225 |            |             |              |             |         |           |                 |
|          210 |            |             |              |             |         |           |                 |
| 300 (repeat) |            |             |              |             |         |           |                 |

**Second table, served preset.** The same sweep on the llama-swap preset
(`Qwen3.8-Flash-Next UD-IQ1_S`, `-ncmoe 26`, `-c 65536`, `q8_0` KV), measured through
`/v1/chat/completions` timings or through `hack/llm-bench.sh`. This table answers the real
question — what a user loses — while the first table answers the physics question.

**Then, and only then,** choose the cap and leave it set. Record the choice in a sibling
`done.md` when the sweep is finished.

### Reading wall power without a PDU

`power1_average` is the **card input power** estimated by the SMU. It is close to what the PSU
delivers on the 12 V rails for the card, and it is not a calibrated shunt. At idle it reads
1–3 W, which is a floor artifact — do not trust idle numbers.

Wall power is larger by three gaps:

- **PSU efficiency.** A Gold unit at 50 % load loses about 10 %. 300 W at the card is about
  333 W at the wall before the rest of the box.
- **The rest of the box.** 5950X package, DDR4, NVMe and fans add 60–150 W depending on load.
  A GPU cap does not remove one watt of that.
- **Transient vs average.** `power1_average` is a moving average. Short spikes above the cap are
  normal and invisible here.

So: use `power1_average` for the _shape_ of the curve and the comparison between caps, and a
wall meter for the absolute number. Never claim a wall figure derived from `power1_average`.

## The helper

`hack/r9700-power.sh`. It is a hand-run tool and is **not wired into any unit, timer or
activation script**. It needs no package on the target, so it works on brys today.

| command                        | effect                                                                                                                                  |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| `show`                         | prints cap, range, default, live power (optionally a mean over N seconds), three temperatures, fan, DPM level, busy percent. Read only. |
| `set <watt>`                   | sets the cap. Prints the old value, needs `--apply`, then reads the value back and fails if it does not match.                          |
| `preset <eco\|balanced\|perf>` | sets a named cap. Same guards as `set`.                                                                                                 |

Safety rules, all tested without writing:

- No `--apply` means no write. The tool prints `old cap X W, target Y W` and exits **2**.
- The old value is printed **before** the write, always.
- A value below `power1_cap_min` is refused with the floor explanation, and a value above
  `power1_cap_max` is refused too, so a typo cannot reach sysfs.
- A value equal to the current one exits 0 and writes nothing.
- The write goes through `sudo -n tee`, then a read-back verifies it. A mismatch is an error.
- The card is found by PCI id `1002:7551`, never by `cardN`.
- `--host HOST` runs the tool over ssh, so it can be driven from `oams`.

It changes nothing until invoked with `--apply`, and it persists nothing. The cap is runtime
state: a reboot or a driver reload returns the card to 300 W.

## Presets

| preset     | watt | why                                                                            |
| ---------- | ---: | ------------------------------------------------------------------------------ |
| `eco`      |  210 | the driver floor, 70 % of the factory cap; the largest saving this card allows |
| `balanced` |  250 | 83 % of the factory cap; the expected knee of the curve                        |
| `perf`     |  300 | the factory default; the full-throttle baseline, and the safe reset            |

`perf` reads `power1_cap_default` from the card at run time, so it stays correct on another
VBIOS. The other two are clamped into the exposed range with a warning.

## Acceptance test

1. The 300 W baseline row exists for both models, with decode, prefill and `power1_average`,
   before any cap is applied.
2. The five-row sweep exists, and the closing 300 W repeat matches the opening row within 5 %.
3. One cap is chosen with a recorded reason: decode within 5 % of baseline on the served preset,
   junction below 90 °C.
4. A first real write has happened and been confirmed by read-back, and the old and the new value
   are in the worklog. Until then the write path stays marked **unverified**.

## Risks and open questions

- **The write path is unverified.** No value has been written. `power1_cap` is writable and the
  code path exists, but only a real write and a read-back prove it on this VBIOS.
- **The floor may be lower on another VBIOS.** 210 W is 70 % of this pptable's value. A VBIOS
  update can move it.
- **A cap is not a thermal fix by itself.** Junction temperature follows fan curve, airflow and
  case temperature. Record all three, not only watt.
- **The box is shared.** `llama-swap` and the metrics relays keep running. A benchmark that
  leaves a stray `llama-server` behind corrupts the next row — this already happened once, see
  [brys-r9700-model-fit](../brys-r9700-model-fit/measurements.md).
- **No persistence is planned.** If a permanent cap is wanted later, it needs a small systemd
  unit with `--apply` baked in. That is a separate decision and deliberately not part of this
  task.
- **PCIe link.** The card sits behind an on-card PCIe switch and the host link is x8. That
  limits the `n-cpu-moe` presets, not the power cap. See
  [brys-r9700-model-fit](../brys-r9700-model-fit/definition.md).

## Sources

Kernel, Linux 6.18 (the version brys runs is 6.18.62):

- `Documentation/gpu/amdgpu/thermal.rst` — the list of power and thermal sysfs interfaces.
- `drivers/gpu/drm/amd/include/amd_shared.h` — `enum PP_FEATURE_MASK`,
  `PP_OVERDRIVE_MASK = 0x4000`.
- `drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c` — `amdgpu_pp_feature_mask = 0xfff7bfff`, with the
  comment "OverDrive(bit 14) disabled by default".
- `drivers/gpu/drm/amd/amdgpu/amdgpu_device.c` — `adev->pm.pp_feature = amdgpu_pp_feature_mask`.
- `drivers/gpu/drm/amd/pm/amdgpu_pm.c` — the hwmon doc block, `power1_cap` mode
  `S_IRUGO | S_IWUSR`, `amdgpu_hwmon_set_power_cap()`, the visibility test for the cap files,
  and the `pp_od_clk_voltage` gate.
- `drivers/gpu/drm/amd/pm/amdgpu_dpm.c` — `amdgpu_dpm_is_overdrive_supported()`,
  `amdgpu_dpm_get_power_limit()`, `amdgpu_dpm_set_power_limit()`.
- `drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c` — `smu_set_funcs()`, `smu_get_power_limit()`,
  `smu_set_power_limit()` and its range check, `smu_get_asic_power_limits()` at init.
- `drivers/gpu/drm/amd/pm/swsmu/smu14/smu_v14_0_2_ppt.c` —
  `smu_v14_0_2_get_power_limit()` (the 70 % floor), `smu_v14_0_2_set_power_limit()`.
- `drivers/gpu/drm/amd/pm/swsmu/smu14/smu_v14_0.c` —
  `smu_v14_0_set_power_limit()` → `SMU_MSG_SetPptLimit`.

Tools:

- `rocm-smi` CLI, `python_smi_tools/rocm_smi.py` in
  [ROCm/rocm-systems](https://github.com/ROCm/rocm-systems/blob/develop/projects/rocm-smi-lib/python_smi_tools/rocm_smi.py)
  — `--showpower`, `--showtemp`, `--setpoweroverdrive`, `--resetpoweroverdrive`, and the
  min/max pre-check in `setPowerOverDrive()`.
- [amdgpu_top](https://github.com/Umio-Yasuno/amdgpu_top) README — TUI, `--json`,
  `--gpu-metrics`; monitoring only.
- [LACT](https://github.com/ilya-zlobintsev/LACT) — `lact-cli/src/subcommands.rs` for
  `power-limit get|set`; [Overclocking (AMD)](https://github.com/ilya-zlobintsev/LACT/blob/master/docs/Overclocking-%28AMD%29.md).
- nixpkgs, pinned in this repo: `pkgs/development/rocm-modules/rocm-smi/default.nix`,
  `pkgs/by-name/am/amdgpu_top/package.nix`, `pkgs/by-name/la/lact/package.nix`,
  `nixos/modules/services/hardware/amdgpu.nix` (`hardware.amdgpu.overdrive`),
  `nixos/modules/services/hardware/lact.nix`.

## Related

- [brys-r9700-model-fit](../brys-r9700-model-fit/definition.md) — the hardware inventory and the
  throughput baseline that this task must not invalidate.
- [brys-power-draw-zigbee](../../2026-10/brys-power-draw-zigbee/definition.md) — the wall meter
  that this task would rather have.
- [w6600-amdgpu-hang](../../2026-10/w6600-amdgpu-hang/definition.md) — the earlier card, the
  `ppfeaturemask` experiments, and why kernel parameters are not free.
- `hack/r9700-power.sh` — the tool.
- `hack/llm-bench.sh` — the serviced-model measurement used by the second table.

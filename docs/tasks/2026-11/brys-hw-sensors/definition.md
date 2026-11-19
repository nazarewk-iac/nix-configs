---
type: Task
description: Read the motherboard temperatures and fan speeds on brys and feed them to the Prometheus that already runs there.
status: open
authored_by: agent
timestamp: 2026-11-19T05:30:29+01:00
---

# Motherboard temperature and fan sensors on brys

## Context

Host `brys` is an ASUS ROG STRIX X570-E GAMING WIFI II with a Ryzen 9 5950X, on the `den`
tree (`hosts-den/brys/`). Before this task the host reported no fan speed and no motherboard
temperature. The only readable temperatures came from three chips that load by themselves:

- `k10temp` (in the CPU): `Tctl`, `Tccd1`, `Tccd2`.
- `asusec` (the ASUS embedded controller): `CPU`, `Motherboard`, `Chipset`, `T_Sensor`, `CPU`
  current.
- `amdgpu` and `nvme`: the GPU and the two NVMe drives.

The SuperIO chip that owns the fan headers and the board thermistors was not bound to any
driver. A fan failure or a blocked filter therefore stayed invisible.

## What the board exposes, measured

The board carries a **Nuvoton NCT6798D**, not the ITE IT8688E that a generic X570 port would
guess. The kernel names the part when the module loads (measured 2026-11-19):

```
$ sudo -n modprobe nct6775
$ journalctl -k | grep nct6775
nct6775: Found NCT6798D or compatible chip at 0x2e:0x290
```

The driver creates one hwmon device with `name` = `nct6798`. `sensors` calls it
`nct6798-isa-0290`. The probe needs no `force_id` argument and no
`acpi_enforce_resources=lax`, because this BIOS does not claim the SuperIO window.

## The NixOS surface

nixpkgs has no general `hardware.sensor` switch and no `services.lm_sensors` service. The only
`hardware.sensor.*` modules are `iio` and `hddtemp`
(`.flake.patches/nixpkgs/repo/nixos/modules/hardware/sensor/`), and `lm_sensors` is a plain
package that the `hw-basic` aspect already installs
(`modules/den/aspects/hw-basic.nix`). The three real switches are:

| Layer    | Switch                                                               | Effect                                                     |
| -------- | -------------------------------------------------------------------- | ---------------------------------------------------------- |
| Kernel   | `boot.kernelModules = [ "nct6775" ]`                                 | binds the NCT6798D at boot, so `/sys/class/hwmon` holds it |
| Exporter | `services.prometheus.exporters.node.enabledCollectors = [ "hwmon" ]` | reads the hwmon tree into `node_hwmon_*`                   |
| CLI      | `environment.etc."sensors.d/brys-nct6798.conf"`                      | gives `libsensors` its labels and ignore list              |

Sample at 2026-11-19T04:30Z, with a build running on the host:

| Chip    | `sensors` label          | sysfs feature     | node_exporter metric                       | Value          | Note                |
| ------- | ------------------------ | ----------------- | ------------------------------------------ | -------------- | ------------------- |
| nct6798 | SYSTIN                   | `temp1`           | `node_hwmon_temp_celsius{sensor="temp1"}`  | 30.0 °C        | board               |
| nct6798 | CPUTIN                   | `temp2`           | `node_hwmon_temp_celsius{sensor="temp2"}`  | 43.0 °C        | socket              |
| nct6798 | AUXTIN0                  | `temp3`           | `node_hwmon_temp_celsius{sensor="temp3"}`  | 91.0 °C        | noise, pin unproven |
| nct6798 | AUXTIN1                  | `temp4`           | `node_hwmon_temp_celsius{sensor="temp4"}`  | 30.0 °C        |                     |
| nct6798 | AUXTIN2                  | `temp5`           | `node_hwmon_temp_celsius{sensor="temp5"}`  | 26.0 °C        |                     |
| nct6798 | AUXTIN3                  | `temp6`           | `node_hwmon_temp_celsius{sensor="temp6"}`  | 91.0 °C        | noise, pin unproven |
| nct6798 | AUXTIN4                  | `temp7`           | `node_hwmon_temp_celsius{sensor="temp7"}`  | 30.0 °C        |                     |
| nct6798 | PECI Agent 0 Calibration | `temp8`           | `node_hwmon_temp_celsius{sensor="temp8"}`  | 53.0 °C        | CPU package, PECI   |
| nct6798 | Virtual_TEMP             | `temp9`           | `node_hwmon_temp_celsius{sensor="temp9"}`  | 30.0 °C        |                     |
| nct6798 | PCH_CHIP_CPU_MAX_TEMP    | `temp10`          | `node_hwmon_temp_celsius{sensor="temp10"}` | 0.0 °C         | placeholder         |
| nct6798 | PCH_CHIP_TEMP            | `temp11`          | `node_hwmon_temp_celsius{sensor="temp11"}` | 0.0 °C         | placeholder         |
| nct6798 | PCH_CPU_TEMP             | `temp12`          | `node_hwmon_temp_celsius{sensor="temp12"}` | 0.0 °C         | placeholder         |
| nct6798 | TSI0_TEMP                | `temp13`          | `node_hwmon_temp_celsius{sensor="temp13"}` | 64.0 °C        | TSI interface       |
| nct6798 | TSI1_TEMP                | `temp14`          | `node_hwmon_temp_celsius{sensor="temp14"}` | 55.0 °C        | TSI interface       |
| nct6798 | fan1                     | `fan1`            | `node_hwmon_fan_rpm{sensor="fan1"}`        | 693 RPM        | fan attached        |
| nct6798 | fan2                     | `fan2`            | `node_hwmon_fan_rpm{sensor="fan2"}`        | 712 RPM        | fan attached        |
| nct6798 | fan3                     | `fan3`            | `node_hwmon_fan_rpm{sensor="fan3"}`        | 1571 RPM       | fan attached        |
| nct6798 | fan4                     | `fan4`            | `node_hwmon_fan_rpm{sensor="fan4"}`        | 0 RPM          | header empty        |
| nct6798 | fan5                     | `fan5`            | `node_hwmon_fan_rpm{sensor="fan5"}`        | 0 RPM          | header empty        |
| nct6798 | fan6                     | `fan6`            | `node_hwmon_fan_rpm{sensor="fan6"}`        | 0 RPM          | header empty        |
| asusec  | CPU                      | n/a               | `node_hwmon_temp_celsius`                  | 52.0 °C        | EC                  |
| asusec  | Motherboard              | n/a               | `node_hwmon_temp_celsius`                  | 29.0 °C        | EC                  |
| asusec  | Chipset                  | n/a               | `node_hwmon_temp_celsius`                  | 55.0 °C        | EC                  |
| asusec  | T_Sensor                 | n/a               | `node_hwmon_temp_celsius`                  | 24.0 °C        | EC                  |
| k10temp | Tctl                     | `temp1`           | `node_hwmon_temp_celsius`                  | 63.8 °C        | CPU                 |
| k10temp | Tccd1 / Tccd2            | `temp3` / `temp4` | `node_hwmon_temp_celsius`                  | 61.0 / 52.0 °C | CPU CCDs            |

Every row's `chip` label names the device: `platform_nct6775_656` for the NCT6798D,
`platform_asus_ec_sensors` for the EC, and a `platform_`/`pci_` name for `k10temp`. The
`sensors` label is also a metric:
`node_hwmon_sensor_label{chip="platform_nct6775_656",sensor="temp1",label="SYSTIN"} 1`.
A query can join that metric to get the vendor name, so a dashboard needs no hard-coded sensor
numbers.

Three findings drive the implementation:

1. **The driver was not loaded.** `/etc/modules-load.d/nixos.conf` listed no `nct6775`, and
   `lsmod` showed no `nct6775`. The chip is a SuperIO device, so it does not hot-plug, and no
   modalias alias loads the driver. `boot.kernelModules = [ "nct6775" ]` is the whole fix.
2. **The existing exporter already carries hwmon.** The node_exporter that `hosts-den/brys/llm.nix`
   runs on `127.0.0.1:9100` has `hwmon` in its default collector set. Its `ExecStart` before this
   change passed only `--collector.textfile`, yet `node_hwmon_*` metrics were already present for
   `asusec`, `k10temp`, `amdgpu` and `nvme`. No new exporter, no textfile collector and no extra
   scrape job is needed.
3. **`hwmon` is not obvious in the config.** nixpkgs documents `enabledCollectors` as "enabled in
   addition to the default ones"
   (`nixos/modules/services/monitoring/prometheus/exporters/node.nix`). The host names `hwmon`
   explicitly, so a later edit to the narrow collector list cannot drop the board without a
   visible diff.

## How the values reach Prometheus

The path already exists and this task adds no parallel stack:

```
/sys/class/hwmon/hwmonN  ->  node_exporter :9100 (host loopback)
                         ->  socat relay on 10.233.90.1:9100
                         ->  Prometheus container 10.233.90.2:9090 (job "node", 30s)
                         ->  https://prometheus.brys.priv.nb.net.int.kdn.im (web exposure)
```

The relay and the scrape job live in `hosts-den/brys/llm.nix`. The container is deliberately not
`kdn.monitoring-prometheus-stack`; it is one small Prometheus with two jobs (`llama-swap`, `node`).

## Implementation

- `hosts-den/brys/sensors.nix` (new): loads `nct6775`, names the `hwmon` collector, and installs
  `/etc/sensors.d/brys-nct6798.conf`.
- `hosts-den/brys/default.nix`: one entry in the `den.aspects.brys.nixos` `imports` list.

The `sensors.d` file is a libsensors hint only: it hides the channels that read bogus values
(`temp3` and `temp6`, assumed unconnected; `temp10..temp12`, which read 0; `fan4..fan6`,
`intrusion0/1`, and the rails without limits) from `sensors`. It does not change node_exporter,
which reads sysfs. The plain `chip` statement holds no braces; `man 5 sensors.conf` defines the
format, and a `chip` statement applies to every line after it.

## Verification

```sh
$ nix eval --no-eval-cache --raw '.#denConfigurations.brys.config.system.build.toplevel.drvPath'
/nix/store/ycbkwkxp1m067azqr6c4pxwl2s1gnbbk-nixos-system-brys-26.11.20261106.296d5fa.drv
```

The flake source is a git fetcher, so a brand-new untracked file is invisible to `.#` until git
knows it (`git ls-files`; see
[nix-conventions.md](../../../../.agents/rules/nix-conventions.md)). `git add
hosts-den/brys/sensors.nix` before the eval resolved that; the file stays untracked in the
working copy after the run.

The merged values, read from the same evaluation:

```
config.boot.kernelModules                          ["atkbd","bridge","cpufreq_performance","ctr",
                                                    "loop","macvlan","nct6775","ryzen-smu","tap",
                                                    "tun","uinput","usbip_host","v4l2loopback",
                                                    "vhci-hcd","zfs"]
config.services.prometheus.exporters.node
  .enabledCollectors                               ["textfile","hwmon"]
systemd.services.prometheus-node-exporter
  .serviceConfig.ExecStart                         … --collector.textfile --collector.hwmon …
```

Live checks on `brys` (read-only, plus one `modprobe`):

```sh
$ sudo -n modprobe nct6775              # rc=0, no argument needed
$ ls /sys/class/hwmon/hwmon12/name
nct6798
$ curl -s http://127.0.0.1:9100/metrics | grep -c '^node_hwmon'
493
```

The `sensors.d` fragment was tested by writing it to `/etc/sensors.d/` for one run, then removing
it: `sensors nct6798-isa-0290` lost exactly the ignored channels and printed no parse error.

The module is **not** built, switched or activated yet. The live host still runs without
`nct6775` at boot: the module above was loaded by hand for this measurement, and a reboot
removes it until the next `nixos-rebuild switch`.

## Open questions

- **`AUXTIN0`/`AUXTIN3` are assumed unconnected.** They read near 90 °C at idle, above their own
  80 °C limit, and moved about 3 °C while the CPU went from 32 to 64 °C. ASUS boards report the
  same two channels as unconnected or flaky
  ([lm-sensors thread](https://unix.stackexchange.com/questions/341815/lm-sensors-crazy)), and a
  real 88 °C rail at idle would be alarming. A BIOS hardware-monitor reading, or a probe on the
  header, settles it. If one turns out real, delete its `ignore` line in
  `hosts-den/brys/sensors.nix`.
- **Fan header names are unverified.** `fan1`..`fan3` carry the three spinning fans and
  `fan4`..`fan6` read 0, but which physical header (`CPU_FAN`, `CPU_OPT`, `CHA_FAN1..3`,
  `AIO_PUMP`) each channel maps to needs a case check or a BIOS fan-report screenshot. Do not
  label them until then.
- **Prometheus still carries the noise.** `temp3` and `temp6` (91 °C on a 30 °C board) reach
  Prometheus, because the ignore list belongs to libsensors. A dashboard must filter them, or a
  recording rule must drop them. Both would need an edit to the scrape config in
  `hosts-den/brys/llm.nix`, which another track owns.
- **No alert exists yet.** A `node_hwmon_fan_rpm == 0` alert on `fan1..fan3`, and a `SYSTIN`
  threshold, would be the useful follow-up. The Prometheus here has no alerting rules today.
- **Fan control is out of scope.** `pwm1_enable`..`pwm6_enable` are all 5 (the chip's automatic
  mode), so the BIOS owns the curve. `services.fancontrol` would fight it and needs its own task.

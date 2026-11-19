# Motherboard temperature and fan sensors on brys.
#
# ## The chip
#
# The ASUS ROG STRIX X570-E GAMING WIFI II carries a Nuvoton NCT6798D SuperIO chip. The
# `nct6775` kernel driver drives it. Measured on the live host, 2026-11-19:
#
#     nct6775: Found NCT6798D or compatible chip at 0x2e:0x290
#
# The probe creates one hwmon device with `name` = `nct6798`: six fan tachometers, fourteen
# temperature channels and fourteen voltage inputs. The board is not the ITE IT8688E that a
# generic X570 port would guess; the kernel names the part, so the driver is `nct6775` and no
# `force_id` argument is needed.
#
# ## Why this file names the driver
#
# The chip sits in an ACPI-claimed SuperIO window: it does not hot-plug, and no alias loads the
# driver on demand. Before this file, `/etc/modules-load.d/nixos.conf` on brys listed no
# `nct6775`, so every fan and every board temperature was invisible. Only `k10temp` (CPU) and
# `asusec` (the ASUS embedded controller: CPU, Motherboard, Chipset, T_Sensor) reported.
# `boot.kernelModules` adds one line to that file, so the chip exists from boot for every reader
# below.
#
# ## How the values reach Prometheus
#
# Through the node_exporter that `llm.nix` already runs on 127.0.0.1:9100 and relays to the
# confined Prometheus container at 10.233.90.1:9100. The board needs no new exporter, no
# textfile and no extra scrape job: the `hwmon` collector reads `/sys/class/hwmon` directly, and
# it reports three families per chip:
#
#     node_hwmon_temp_celsius{chip="platform_nct6775_656",sensor="temp1"} 29
#     node_hwmon_fan_rpm{chip="platform_nct6775_656",sensor="fan1"} 694
#     node_hwmon_sensor_label{chip="platform_nct6775_656",sensor="temp1",label="SYSTIN"} 1
#
# `node_hwmon_sensor_label` carries the vendor name (SYSTIN, CPUTIN, TSI0_TEMP, ...), so a query
# can join it instead of hard-coding sensor numbers. Measured: all three families appear within
# one scrape of the module load, and node_exporter needs no restart, because it rescans the
# directory on every scrape.
#
# `hwmon` is one of node_exporter's default collectors (the unit runs with `--collector.textfile`
# as its only collector flag, and the `node_hwmon_*` families are already present). The line below
# names it anyway: this exporter is configured with a narrow collector list in `llm.nix`, and a
# later edit must not drop the board without a visible diff. nixpkgs documents `enabledCollectors`
# as "enabled in addition to the default ones".
#
# The `chip` label is the platform-device name, so its numeric suffix may differ on another boot.
# Match `node_hwmon_chip_names{chip_name="nct6798"}` and join on `chip`, never a hard-coded suffix.
#
# ## What `sensors` shows, and what it hides
#
# `/etc/sensors.d/brys-nct6798.conf` is the libsensors view of the same chip, minus the channels
# that read bogus values on this board. The NCT6798D reports fourteen temperatures and fourteen
# rails, and this BIOS leaves many of them unwired: AUXTIN0 and AUXTIN3 read near 90 C, above
# their own 80 C limit, beside a 30 C board, and ten rails report `ALARM` because their limit is
# 0. ASUS boards report the same two channels as unconnected or flaky
# (https://unix.stackexchange.com/questions/341815/lm-sensors-crazy). A permanent alarm trains a
# reader to ignore alarms, so those channels are ignored in the CLI. Delete an `ignore` line to
# bring its channel back; the assumption behind it is recorded in the task file.
#
# The ignore list is a libsensors hint only. Prometheus still carries every channel, because
# node_exporter reads sysfs and not libsensors. Treat `temp3` and `temp6` as noise in a query.
#
# ## What this file does not do
#
# It sets no fan curve and no limit. `pwm1_enable`..`pwm6_enable` are all 5, the chip's own
# automatic mode, so the board firmware owns the fans and a write here would fight it.
{
  ...
}:
{
  boot.kernelModules = [ "nct6775" ];

  services.prometheus.exporters.node.enabledCollectors = [ "hwmon" ];

  environment.etc."sensors.d/brys-nct6798.conf".text = ''
    # The Nuvoton NCT6798D on the ASUS ROG STRIX X570-E GAMING WIFI II. libsensors calls the chip
    # `nct6798-isa-0290`; that is the first line `sensors` prints for it.
    #
    # A `chip` statement applies to every line after it, so this fragment holds one chip block and
    # ends at end of file. See `man 5 sensors.conf` for the format: there are no braces.
    #
    # The file contains `ignore` lines only. The feature names below are the raw sysfs names
    # (`sensors -u` prints the same), and the vendor labels from the driver stay as they are.
    chip "nct6798-isa-0290"

    # Temperature channels with no sensor attached. Measured 2026-11-19: AUXTIN0 and AUXTIN3 read
    # near 90 C, above their own 80 C limit, while the board reads 30 C. temp10..temp12 are PCH
    # placeholders that read 0. Remove a line here to show that channel again.
    ignore temp3
    ignore temp6
    ignore temp10
    ignore temp11
    ignore temp12

    # Fan headers with no fan attached. Measured 0 RPM on all three.
    ignore fan4
    ignore fan5
    ignore fan6

    # Chassis-intrusion pins: not wired on this board.
    ignore intrusion0
    ignore intrusion1

    # Voltage rails the BIOS left without limits (`*_max` = 0), so each one reports a false ALARM.
    # in0 keeps its real 1.744 V limit and stays visible.
    ignore in1
    ignore in2
    ignore in3
    ignore in4
    ignore in6
    ignore in7
    ignore in8
    ignore in9
    ignore in10
    ignore in11
    ignore in12
    ignore in13
    ignore in14
  '';
}

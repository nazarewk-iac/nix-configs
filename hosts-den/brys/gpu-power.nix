# Board-power cap for the R9700.
#
# The card accepts a cap in `power1_cap` with a floor the SMU reads once at init: 210 W here
# (`power1_cap_min`). Anything below is refused with `EINVAL` and the card keeps its previous
# value, so 210 W is the lowest reachable setting on this VBIOS — not a choice, a wall.
#
# Measured 2026-11-20 (`docs/tasks/2026-11/r9700-power-limit/solution.md`): at 210 W the frontier
# decodes within a few percent of 300 W in every profile, long prefill loses about a third, and the
# card stays stable under sustained load. 300 W buys 60 W of heat for that prefill.
#
# The cap is not persisted by the driver: after a reboot, a suspend or a `systemctl restart
# systemd-modules-load`, the card is back at its factory 300 W. This unit writes it once per boot
# and fails loudly if the read-back disagrees, so a kernel or VBIOS change that moves the floor
# shows up in `systemctl status` instead of silently leaving the card at 300 W.
{
  pkgs,
  lib,
  ...
}:
let
  # 210 W: `power1_cap_min` on this card. The script clamps to whatever the kernel advertises, so a
  # different VBIOS or kernel still gets a legal value rather than an error.
  targetMw = 210000000;

  apply = pkgs.writeShellScript "r9700-power-cap" ''
    set -euo pipefail
    target=${toString targetMw}
    # The hwmon attributes appear once amdgpu has probed the card; wait for them rather than depend
    # on `systemd-udev-settle` (which the kernel documentation asks you not to use).
    i=0
    while [ "$i" -lt 30 ]; do
      set -- /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap
      [ -e "$1" ] && break
      sleep 1
      i=$((i + 1))
    done
    applied=0
    for cap in /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap; do
      [ -w "$cap" ] || continue
      # Only the R9700 (`1002:7551`). The box also holds a Radeon 550 for display output, and a
      # board-power cap written to that card is meaningless — it used to be clamped to its own
      # ceiling and reported as if it mattered.
      if ! grep -q "PCI_ID=1002:7551" "$(dirname "$(dirname "$cap")")/../uevent" 2>/dev/null; then
        continue
      fi
      min=$(cat "$(dirname "$cap")/power1_cap_min" 2>/dev/null || echo 0)
      max=$(cat "$(dirname "$cap")/power1_cap_max" 2>/dev/null || echo 0)
      want=$target
      if [ "$min" -gt 0 ] && [ "$want" -lt "$min" ]; then
        echo "r9700-power-cap: $target mW is below this card's floor, using $min mW" >&2
        want=$min
      fi
      if [ "$max" -gt 0 ] && [ "$want" -gt "$max" ]; then
        echo "r9700-power-cap: $target mW is above this card's ceiling, using $max mW" >&2
        want=$max
      fi
      printf '%s\n' "$want" > "$cap"
      now=$(cat "$cap")
      if [ "$now" != "$want" ]; then
        echo "r9700-power-cap: write refused on $cap (asked $want mW, card reports $now mW)" >&2
        exit 1
      fi
      echo "r9700-power-cap: $cap = $((now / 1000000)) W (range $((min / 1000000))-$((max / 1000000)) W)"
      applied=$((applied + 1))
    done
    if [ "$applied" -eq 0 ]; then
      echo "r9700-power-cap: no writable power1_cap found; is the amdgpu module loaded?" >&2
      exit 1
    fi
  '';
in
{
  systemd.services.r9700-power-cap = {
    description = "Cap the R9700 board power at 210 W";
    wantedBy = [ "multi-user.target" ];
    # The hwmon attributes appear with the amdgpu device, which is up long before multi-user.
    after = [ "systemd-modules-load.service" ];
    # The unit runs with systemd's minimal PATH; the script needs `cat`, `grep` and `sleep`.
    path = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${apply}";
    };
  };

  # A suspend drops the SMU's state; re-apply on resume so the card never comes back at 300 W.
  systemd.services.r9700-power-cap-resume = {
    description = "Re-apply the R9700 board power cap after resume";
    wantedBy = [ "suspend.target" ];
    after = [ "systemd-suspend.service" ];
    path = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${apply}";
    };
  };
}

#!/usr/bin/env bash
# Control the board power cap (PPT) of an AMD Radeon AI PRO R9700.
#
# Every read is side-effect free. A write needs `--apply`, prints the old value
# first, and then reads the value back. The tool is not wired into any unit.
# Run it by hand.
#
# The interfaces, the reachable range and the measurement plan are in
# docs/tasks/2026-11/r9700-power-limit/definition.md.
set -eEuo pipefail

readonly PROG="r9700-power.sh"
# The remote run needs the script text, not the current working directory. The
# remote side reads the script from stdin, so BASH_SOURCE can be unset there.
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ]; then SELF="$(readlink -f "$SELF")"; fi
readonly SELF

# Keep the arguments for the remote run. The parse loop drops --host from FWD.
FWD=()

# The R9700 is PCI 1002:7551. There are two AMD GPUs on brys, so the tool must
# select the card by PCI id and never by the card number.
PCI_ID="1002:7551"
HOST=""
APPLY=0
SAMPLE=0
SUBCOMMAND=""
OPERAND=""

# Presets in watt. `perf` is the card default, read from the card at run time.
readonly PRESET_ECO=210
readonly PRESET_BALANCED=250

usage() {
  cat <<'EOF'
Read and change the board power cap of the AMD Radeon AI PRO R9700.

Usage:
  r9700-power.sh [--host HOST] show [--sample SECONDS]
  r9700-power.sh [--host HOST] set <watt> --apply
  r9700-power.sh [--host HOST] preset <eco|balanced|perf> --apply

Commands:
  show                 Print the cap range, the live power, the temperatures and
                       the clocks. Read only.
  set <watt>           Set the board power cap to <watt>. Needs --apply.
  preset <name>        Set one of the named caps. Needs --apply.
                         eco       210 W  the driver floor on this card
                         balanced  250 W
                         perf      the card default (300 W)

Flags:
  --host HOST          Run the commands on HOST over ssh. Default: this machine.
  --apply              Write the new value. Without it the tool prints the plan
                       and exits with code 2.
  --sample SECONDS     In `show`, average power1_average over this window.
                       Default: one read.
  --pci-id ID          PCI vendor:device of the card. Default: 1002:7551.
  --help               Print this help.

Exit codes:
  0  the read succeeded, or the value is already the requested one, or the
     write is verified by a read-back
  1  an error: no card, bad value, out of range, write rejected
  2  a change was requested without --apply

Examples:
  r9700-power.sh --host brys show
  r9700-power.sh --host brys show --sample 10
  r9700-power.sh --host brys preset eco
  r9700-power.sh --host brys preset eco --apply

Notes:
  - A write needs root. The tool calls `sudo -n`; on brys user kdn has
    NOPASSWD: ALL.
  - The cap is runtime state. A reboot or a driver reload returns the card to
    its default cap. This tool never persists anything.
EOF
}

die() {
  echo "$PROG: $*" >&2
  exit 1
}

refuse() {
  echo "$PROG: $*" >&2
  exit 2
}

# ------------------------------------------------------------------ arguments

while [ "$#" -gt 0 ]; do
  case "$1" in
  --host)
    HOST="${2:?--host needs a value}"
    shift 2
    ;;
  --pci-id)
    PCI_ID="${2:?--pci-id needs a value}"
    FWD+=(--pci-id "$PCI_ID")
    shift 2
    ;;
  --apply)
    APPLY=1
    FWD+=(--apply)
    shift
    ;;
  --sample)
    SAMPLE="${2:?--sample needs a value}"
    FWD+=(--sample "$SAMPLE")
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  -*)
    die "unknown flag: $1 (see --help)"
    ;;
  *)
    if [ -z "$SUBCOMMAND" ]; then
      SUBCOMMAND="$1"
    elif [ -z "$OPERAND" ]; then
      OPERAND="$1"
    else
      die "unexpected argument: $1 (see --help)"
    fi
    FWD+=("$1")
    shift
    ;;
  esac
done

case "$SAMPLE" in '' | *[!0-9]*) die "--sample needs a whole number of seconds" ;; esac

# Run the rest of the tool on the target machine. The script goes over stdin, so
# no quoting is needed and the remote shell never parses an argument. FWD drops
# --host, so the remote run stays local.
if [ -n "$HOST" ]; then
  [ -n "$SELF" ] || die "cannot read the script path for the remote run"
  exec ssh -o BatchMode=yes "$HOST" bash -s -- "${FWD[@]}" <"$SELF"
fi

# ------------------------------------------------------------------ discovery

# Set by resolve_card.
CARD_DEV=""
HWMON=""

resolve_card() {
  local dev vendor device hw
  for dev in /sys/class/drm/card*/device; do
    [ -r "$dev/vendor" ] || continue
    vendor="$(cat "$dev/vendor")"
    device="$(cat "$dev/device")"
    # vendor and device are 0x1002 and 0x7551 style strings.
    if [ "${vendor#0x}${device#0x}" = "$(echo "$PCI_ID" | tr -d ':')" ]; then
      CARD_DEV="$dev"
      break
    fi
  done
  [ -n "$CARD_DEV" ] || die "no card with PCI id $PCI_ID. Is amdgpu loaded?"
  for hw in "$CARD_DEV"/hwmon/hwmon*; do
    [ -e "$hw/power1_cap" ] || continue
    HWMON="$hw"
    break
  done
  [ -n "$HWMON" ] || die "card $CARD_DEV exposes no hwmon power1_cap"
}

attr() {
  # attr PATH DEFAULT: print the file content, or DEFAULT when unreadable.
  local path="$1" fallback="${2:-?}"
  if [ -r "$path" ]; then cat "$path"; else printf '%s' "$fallback"; fi
}

# Microwatt to watt, as an integer.
uw_to_w() {
  local uw="$1"
  case "$uw" in '' | *[!0-9]*) printf '?'; return 0 ;; esac
  printf '%d' "$((uw / 1000000))"
}

# Millidegree Celsius to degree Celsius, as an integer.
uw_to_millideg() {
  local v="$1"
  case "$v" in '' | *[!0-9]*) printf '?'; return 0 ;; esac
  printf '%d' "$((v / 1000))"
}

# ------------------------------------------------------------------ commands

show_power_stats() {
  local hw="$1" seconds="$2"
  local raw mean lowest highest now count=0 sum=0
  raw="$(attr "$hw/power1_average" '')"
  printf 'power1_average      %s W\n' "$(uw_to_w "${raw:-}")"
  if [ "$seconds" -le 0 ]; then return 0; fi
  lowest=""
  highest=""
  # Sample twice per second for the requested window. power1_average is the SMU
  # moving average of the board input power.
  local max_reads=$((seconds * 2))
  while [ "$count" -lt "$max_reads" ]; do
    now="$(attr "$hw/power1_average" '')"
    case "$now" in
    '' | *[!0-9]*) ;;
    *)
      sum=$((sum + now))
      count=$((count + 1))
      if [ -z "$lowest" ] || [ "$now" -lt "$lowest" ]; then lowest="$now"; fi
      if [ -z "$highest" ] || [ "$now" -gt "$highest" ]; then highest="$now"; fi
      ;;
    esac
    sleep 0.5
  done
  [ "$count" -gt 0 ] || return 0
  mean=$((sum / count))
  printf 'power mean          %s W over %d s (%s samples, min %s W, max %s W)\n' \
    "$(uw_to_w "$mean")" "$seconds" "$count" \
    "$(uw_to_w "$lowest")" "$(uw_to_w "$highest")"
}

cmd_show() {
  local cap min max default
  min="$(attr "$HWMON/power1_cap_min" '')"
  max="$(attr "$HWMON/power1_cap_max" '')"
  cap="$(attr "$HWMON/power1_cap" '')"
  default="$(attr "$HWMON/power1_cap_default" '')"

  printf 'card                %s (%s)\n' "$PCI_ID" "$CARD_DEV"
  printf 'hwmon               %s\n' "$HWMON"
  printf 'power1_cap          %s W\n' "$(uw_to_w "$cap")"
  printf 'power1_cap_min      %s W\n' "$(uw_to_w "$min")"
  printf 'power1_cap_max      %s W\n' "$(uw_to_w "$max")"
  printf 'power1_cap_default  %s W\n' "$(uw_to_w "$default")"
  show_power_stats "$HWMON" "$SAMPLE"
  printf 'temp edge           %s C\n' "$(uw_to_millideg "$(attr "$HWMON/temp1_input" '')")"
  printf 'temp junction       %s C\n' "$(uw_to_millideg "$(attr "$HWMON/temp2_input" '')")"
  printf 'temp mem            %s C\n' "$(uw_to_millideg "$(attr "$HWMON/temp3_input" '')")"
  printf 'fan1_input          %s rpm\n' "$(attr "$HWMON/fan1_input" '')"
  printf 'dpm level           %s\n' "$(attr "$CARD_DEV/power_dpm_force_performance_level" '?')"
  printf 'gpu_busy_percent    %s\n' "$(attr "$CARD_DEV/gpu_busy_percent" '?')"
  printf 'mem_busy_percent    %s\n' "$(attr "$CARD_DEV/mem_busy_percent" '?')"
}

# apply_cap TARGET_W LABEL is the single write path.
apply_cap() {
  local target="$1" label="${2:-set}"
  local min max cap old_w target_uw new_w

  min="$(attr "$HWMON/power1_cap_min" '')"
  max="$(attr "$HWMON/power1_cap_max" '')"
  cap="$(attr "$HWMON/power1_cap" '')"
  case "$min$max$cap" in
  *[!0-9]*) die "cannot read the cap range from $HWMON" ;;
  esac

  old_w="$(uw_to_w "$cap")"
  if [ "$target" -lt "$(uw_to_w "$min")" ]; then
    die "$target W is below the driver floor of $(uw_to_w "$min") W.
  This card computes the floor as 70 % of the pptable socket power limit.
  Values below it need a pptable change, not a sysfs write."
  fi
  if [ "$target" -gt "$(uw_to_w "$max")" ]; then
    die "$target W is above the exposed maximum of $(uw_to_w "$max") W.
  A value above the maximum needs the overdrive bit (amdgpu.ppfeaturemask)."
  fi

  echo "$label: old cap $old_w W, target $target W"
  if [ "$target" = "$old_w" ]; then
    echo "$PROG: the card is already at $target W; nothing to do."
    exit 0
  fi

  if [ "$APPLY" -eq 0 ]; then
    refuse "refusing to write without --apply. Re-run with --apply to set $target W."
  fi

  target_uw=$((target * 1000000))
  printf '%s\n' "$target_uw" | sudo -n tee "$HWMON/power1_cap" >/dev/null ||
    die "the write to $HWMON/power1_cap failed"

  new_w="$(uw_to_w "$(attr "$HWMON/power1_cap" '')")"
  if [ "$new_w" != "$target" ]; then
    echo "$PROG: read-back is $new_w W, not $target W. The driver clamped or" \
      "ignored the value. Treat the card as unchanged." >&2
    exit 1
  fi
  echo "new cap $new_w W (verified by read-back)"
  echo "note: the cap is runtime state and returns to the default on reboot."
}

cmd_set() {
  case "$OPERAND" in '' | *[!0-9]*) die "set needs a whole number of watt" ;; esac
  apply_cap "$OPERAND" "set"
}

cmd_preset() {
  local name="${OPERAND:-}" target
  case "$name" in
  eco) target="$PRESET_ECO" ;;
  balanced) target="$PRESET_BALANCED" ;;
  perf | '')
    target="$(uw_to_w "$(attr "$HWMON/power1_cap_default" '')")"
    case "$target" in
    '?') die "cannot read power1_cap_default for the perf preset" ;;
    esac
    ;;
  *) die "unknown preset: $name (use eco, balanced or perf)" ;;
  esac

  # Clamp into the exposed range. A card with other limits must not fail here.
  local min max
  min="$(uw_to_w "$(attr "$HWMON/power1_cap_min" '')")"
  max="$(uw_to_w "$(attr "$HWMON/power1_cap_max" '')")"
  case "$min$max" in
  *\?*) : ;;
  *)
    if [ "$target" -lt "$min" ]; then
      echo "$PROG: preset $name is $target W, clamped up to the floor $min W" >&2
      target="$min"
    fi
    if [ "$target" -gt "$max" ]; then
      echo "$PROG: preset $name is $target W, clamped down to the maximum $max W" >&2
      target="$max"
    fi
    ;;
  esac

  apply_cap "$target" "preset $name"
}

# ------------------------------------------------------------------ run

case "$SUBCOMMAND" in
show | set | preset) resolve_card ;;
'') usage >&2; exit 1 ;;
*) die "unknown command: $SUBCOMMAND (see --help)" ;;
esac

case "$SUBCOMMAND" in
show) cmd_show ;;
set) cmd_set ;;
preset) cmd_preset ;;
esac

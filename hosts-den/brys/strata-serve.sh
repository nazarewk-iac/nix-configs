#!/usr/bin/env bash
# One llama-swap entry point for each Strata operating profile.
#
# llama-swap spawns `cmd` and proxies to `--port`; Strata's own `launch` detaches, so the only
# foreground server is `strata serve --profile <config>`. This script materialises a profile
# config (the per-model config that `strata launch` wrote, with the profile's engine args patched
# in) and execs `strata serve` on the port llama-swap hands over.
#
# Profiles, measured 2026-11-19 (docs/tasks/2026-11/brys-r9700-model-fit/measurements.md):
#   max        UD-IQ4_XS, whole card, 1M           73.1 t/s, no companion
#   omni-max   UD-IQ4_XS, 21.5 GB reserve, 1M      42.3 t/s + omni at 101 t/s (16k)
#   omni-fast  IQ2_XS,    21.5 GB reserve, 1M      71.6 t/s + omni at 101 t/s (16k)
#
# Usage: strata-serve <max|omni-max|omni-fast> --port N
set -uo pipefail

# Strata's data folder on brys, NOT the caller's generic XDG_DATA_HOME (which a login
# shell sets to ~/.local/share and which holds no Terminal).
DATA=${STRATA_DATA_HOME:-/var/lib/kdn/llms/models/.bench/xdg}
INSTALL="$DATA/strata/install"
PROFILES="$DATA/strata/profiles"
SHIM=${ROCM_SHIM:-/var/lib/kdn/llms/models/.bench/rocm-skip.so}
[ -r "$SHIM" ] && export LD_PRELOAD="$SHIM"
# llama-swap runs this as a DynamicUser with no home; Strata derives a data path from HOME.
export HOME="${HOME:-${RUNTIME_DIRECTORY:-/tmp}}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-/var/lib/kdn/llms/models/.bench/xdg}"

profile=${1:-max}; shift || true
port=8080
while [ $# -gt 0 ]; do
  case "$1" in
    --port) port=$2; shift 2 ;;
    *) shift ;;
  esac
done

case "$profile" in
  # `parallel` is `strata serve`'s slot count; it reaches the engine as `--batch N` (verified with
  # `strata serve --plan`: `--parallel 8` appends `--batch 8` to the engine argv). The engine's
  # maximum is 8, but each slot pins its own K/V for the whole `--max-context` (~15.8 GiB at 1M,
  # measured on brys 2026-11-21). The host has 125 GiB and no swap, and the pack's experts are
  # already locked in RAM, so the wall is RAM:
  #   8 slots  -> Shmem 89.7 GB, OOM-killed at 125 GiB used
  #   max/omni-max (55 GiB pack) at 2 -> OOM-killed, engine RSS 109.6 GiB
  #   omni-fast (35 GiB pack) at 2    -> loads and serves, MemAvailable 7.8 GiB
  # So the concurrency lives on `omni-fast` and the whole-card profiles keep 1 slot. The manager's
  # profile table (`internal/engine/strata`) and `config.json` carry the same numbers; this script is
  # the manual `strata-frontier` fallback.
  #
  # `kvres` is `--kv-resident`: cells of each QSA layer kept in VRAM, a per-layer streaming window
  # shared by the slots, not a per-slot allocation. 32768 cells is 8 slots x 4k, which is why the
  # three frontier profiles now agree on it: the omni profiles ran 4096 (512 cells per slot at 8
  # slots) and would have streamed almost every token of a slot's context from RAM. `strata serve`
  # lowers it further when the sessions do not leave room on the card.
  max)       base=unsloth-ud-iq4_xs; reserve=1024;  kvres=32768; parallel=1 ;;
  omni-max)  base=unsloth-ud-iq4_xs; reserve=21500; kvres=32768; parallel=1 ;;
  omni-fast) base=iq2_xs;            reserve=21500; kvres=32768; parallel=2 ;;
  *) echo "strata-serve: unknown profile '$profile'" >&2; exit 2 ;;
esac

src="$INSTALL/strata-$base.json"
[ -r "$src" ] || { echo "strata-serve: no config at $src; run 'strata launch --model $base' once" >&2; exit 1; }
# llama-swap runs this under a sandboxed DynamicUser: the dataset is read-only there, so the
# materialised config goes to the unit's runtime directory (or /tmp) when PROFILES is not writable.
out_dir=$PROFILES
if ! mkdir -p "$out_dir" 2>/dev/null || [ ! -w "$out_dir" ]; then
  out_dir=${RUNTIME_DIRECTORY:-${TMPDIR:-/tmp}}
fi
dst="$out_dir/strata-$profile.json"

python3 - "$src" "$dst" "$reserve" "$kvres" <<'PY'
import json, sys
src, dst, reserve, kvres = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
cfg = json.load(open(src))
args = list(cfg.get("args") or [])
def set_arg(flag, value):
    if flag in args:
        args[args.index(flag) + 1] = value
    else:
        args.extend([flag, value])
set_arg("--vram-reserve-mib", reserve)
set_arg("--kv-resident", kvres)
cfg["args"] = args
json.dump(cfg, open(dst, "w"), indent=1)
PY

# The Terminal's own launcher, run through nix-ld. The `pkgs.kdn.strata` FHS wrapper cannot be used
# here: llama-swap's sandbox forbids the user namespace bubblewrap needs.
exec "${STRATA_BIN:-/var/lib/kdn/llms/models/.bench/bin/strata}" serve --profile "$dst" \
  --host 127.0.0.1 --port "$port" --parallel "$parallel"

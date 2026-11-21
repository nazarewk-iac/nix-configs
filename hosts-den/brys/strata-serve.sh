#!/usr/bin/env bash
# One llama-swap entry point for each Strata operating profile.
#
# llama-swap spawns `cmd` and proxies to `--port`; Strata's own `launch` detaches, so the only
# foreground server is `strata serve --profile <config>`. This script materialises a profile
# config (the per-model config that `strata launch` wrote, with the profile's engine args patched
# in) and execs `strata serve` on the port llama-swap hands over.
#
# Profiles, measured 2026-11-21 (docs/tasks/2026-11/brys-r9700-model-fit/measurements.md):
#   max-multi   UD-IQ4_XS, whole card, 384k x 8    31.9 t/s aggregate, 8.3 GiB free
#   max-swarm   UD-IQ4_XS, whole card, 256k x 8    36.2 t/s aggregate, 18.8 GiB free
#   max-long    UD-IQ4_XS, whole card,   1M x 2    29.7 t/s aggregate, 10.8 GiB free
#   fast-swarm  IQ2_XS,    whole card, 384k x 8    61.0 t/s aggregate, 32.1 GiB free
#   omni-max    UD-IQ4_XS, 21.5 GB reserve, 1M     42.3 t/s + omni at 101 t/s (16k)
#   omni-fast   IQ2_XS,    21.5 GB reserve, 1M     71.6 t/s + omni at 101 t/s (16k)
#
# Usage: strata-serve <max-multi|max-swarm|max-long|fast-swarm|omni-max|omni-fast> --port N
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
  # `strata serve --plan`: `--parallel 8` appends `--batch 8` to the engine argv). Each slot carves
  # its own K/V for the whole `--max-context` at start-up: 9.56 KiB per cell with k8v4, so 2.39 GiB
  # for a 256k slot, 3.59 GiB for a 384k slot and 9.56 GiB for a 1M slot. The host has 125 GiB and
  # no swap, so the wall is RAM. Measured 2026-11-21, one load per row:
  #
  #   max-multi   8 x 384k   28.7 GiB K/V    8.3 GiB free   31.9 t/s   the resting profile
  #   max-swarm   8 x 256k   19.1 GiB K/V   18.8 GiB free   36.2 t/s   the same slots, more RAM
  #   max-long      2 x 1M   19.1 GiB K/V   10.8 GiB free   29.7 t/s   long sessions
  #   fast-swarm  8 x 384k   28.7 GiB K/V   32.1 GiB free   61.0 t/s   IQ2_XS, concurrency
  #
  # Eight is the engine's cap (SLOTS_MAX). Two settings make the fit, both measured: `--ple-io mmap`
  # keeps the ~30 GiB n-gram table in the page cache instead of locking it (locking it is what made
  # a second 1M slot OOM and a 384k load take 126 s), and a 2 GiB park pool spends RAM on live slots
  # rather than parked conversations. The manager's profile table (`internal/engine/strata`) and
  # `config.json` carry the same numbers; this script is the manual `strata-frontier` fallback.
  #
  # `kvres` is `--kv-resident`: cells of each QSA layer kept in VRAM, a per-layer streaming window
  # shared by the slots, not a per-slot allocation. 32768 cells is 8 slots x 4k, which is why the
  # three frontier profiles now agree on it: the omni profiles ran 4096 (512 cells per slot at 8
  # slots) and would have streamed almost every token of a slot's context from RAM. `strata serve`
  # lowers it further when the sessions do not leave room on the card.
  max-multi)  base=unsloth-ud-iq4_xs; reserve=1024;  kvres=32768; parallel=8; ctx=393216;  rope=1.5; cc=2048; ple=mmap ;;
  max-swarm)  base=unsloth-ud-iq4_xs; reserve=1024;  kvres=32768; parallel=8; ctx=262144;  rope=1;   cc=2048; ple=mmap ;;
  max-long)   base=unsloth-ud-iq4_xs; reserve=1024;  kvres=32768; parallel=2; ctx=1048576; rope=4;   cc=1024; ple=mmap ;;
  fast-swarm) base=iq2_xs;            reserve=1024;  kvres=32768; parallel=8; ctx=393216;  rope=1.5; cc=2048; ple=mmap ;;
  omni-max)   base=unsloth-ud-iq4_xs; reserve=21500; kvres=32768; parallel=1; ctx=;       rope=;   cc=;    ple= ;;
  omni-fast)  base=iq2_xs;            reserve=21500; kvres=32768; parallel=2; ctx=;       rope=;   cc=;    ple= ;;
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

python3 - "$src" "$dst" "$reserve" "$kvres" "$ctx" "$rope" "$cc" "$ple" <<'PY'
import json, sys
src, dst, reserve, kvres, ctx, rope, cc, ple = sys.argv[1:9]
cfg = json.load(open(src))
args = list(cfg.get("args") or [])
def set_arg(flag, value):
    if flag in args:
        args[args.index(flag) + 1] = value
    else:
        args.extend([flag, value])
set_arg("--vram-reserve-mib", reserve)
set_arg("--kv-resident", kvres)
# Empty means "keep the base config's value": the omni profiles still serve the 1M window with the
# n-gram table locked in RAM, which is what their 21.5 GiB reserve was measured with.
if ctx:
    set_arg("--max-context", ctx)
if rope:
    set_arg("--rope-scale", rope)
if cc:
    set_arg("--conversation-cache-mib", cc)
if ple:
    set_arg("--ple-io", ple)
cfg["args"] = args
json.dump(cfg, open(dst, "w"), indent=1)
PY

# The Terminal's own launcher, run through nix-ld. The `pkgs.kdn.strata` FHS wrapper cannot be used
# here: llama-swap's sandbox forbids the user namespace bubblewrap needs.
exec "${STRATA_BIN:-/var/lib/kdn/llms/models/.bench/bin/strata}" serve --profile "$dst" \
  --host 127.0.0.1 --port "$port" --parallel "$parallel"

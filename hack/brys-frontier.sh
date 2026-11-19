#!/usr/bin/env bash
# Start or stop the brys frontier stack: Strata serving Qwen3.8-Flash-Next at 1M, with a VRAM
# reserve that leaves room for a media model (qwen3-omni-30b-a3b) on the same card.
#
# Measured 2026-11-19 on the R9700 (docs/tasks/2026-11/brys-r9700-model-fit/measurements.md):
#   UD-IQ4_XS  1M + DFlash2 + k8v4 + 20 GB reserve -> ~50 t/s, 104 GiB RAM used, 21 GiB free
#   qwen3-omni-30b-a3b beside it (with its mmproj)  -> 157 t/s, 20 GiB of VRAM
#
# The engine is a signed download, not a Nix package. Its HIP runtime needs the KFD shim while the
# RX 550 is in the box: hack/rocm-skip-legacy-gpu.c.
#
# Usage:
#   hack/brys-frontier.sh up [--pack UD-IQ4_XS]   # start Strata (and print how to load omni)
#   hack/brys-frontier.sh down                    # stop Strata
#   hack/brys-frontier.sh status                  # what is running on the card
set -uo pipefail

# The Terminal's own `strata` is a generic ELF that NixOS cannot start; the FHS wrapper from
# `nix build .#strata` is the one to call. Override with STRATA_BIN when the store path moves.
STRATA=${STRATA_BIN:-$(command -v strata 2>/dev/null || echo /nix/store/kvxg49ar4h8bqqf0qpi1sdvzw4y96l32-strata-0/bin/strata)}
DATA=${STRATA_DATA_HOME:-/var/lib/kdn/llms/models/.bench/xdg}
MODELS=${STRATA_MODELS:-/var/lib/kdn/llms/models/.bench/strata/models}
SHIM=${ROCM_SHIM:-/home/kdn/.local/lib/rocm-skip.so}
LLAMACPP_MODELS=/var/lib/kdn/llms/models/unsloth/Qwen3.8-Flash-Next-GGUF
PORT=${STRATA_PORT:-8080}
VRAM=/sys/class/drm/card1/device/mem_info_vram_used
RESERVE=21500    # MiB left for the media model (omni at 16k needs ~21 GiB)
KV_RESIDENT=4096 # tokens of K/V kept in VRAM; older K/V is read from RAM
CONV_CACHE=15000 # MiB of parked conversation K/V in RAM (~1.5M tokens at 10 KB/token)
MEM_LIMIT=112000 # MiB the engine may use, so the desktop keeps a margin

pack=UD-IQ4_XS
profile=max # the default operating point: the frontier alone on the whole card
action=${1:-status}
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
  --pack)
    pack=$2
    shift 2
    ;;
  --profile)
    profile=$2
    shift 2
    ;;
  *)
    echo "unknown option: $1" >&2
    exit 2
    ;;
  esac
done
# Three operating points, measured 2026-11-19 (task measurements.md):
#   max        UD-IQ4_XS, whole card (1 GB reserve for the draft head)  73.1 t/s, no companion
#   omni-max   UD-IQ4_XS, 21.5 GB reserve                              42.3 t/s + omni 101 t/s
#   omni-fast  IQ2_XS,    21.5 GB reserve                              71.6 t/s + omni 101 t/s
if [ -n "$profile" ]; then
  case "$profile" in
  max)
    pack=UD-IQ4_XS
    RESERVE=1024
    KV_RESIDENT=32768
    ;;
  omni-max)
    pack=UD-IQ4_XS
    RESERVE=21500
    KV_RESIDENT=4096
    ;;
  omni-fast)
    pack=IQ2_XS
    RESERVE=21500
    KV_RESIDENT=4096
    ;;
  *)
    echo "unknown profile: $profile" >&2
    exit 2
    ;;
  esac
fi

model_path() {
  case "$pack" in
  UD-IQ4_XS | UD-Q4_K_XL | UD-Q5_K_XL) echo "$LLAMACPP_MODELS/$pack" ;;
  Coder) echo "$MODELS/coder-IQ1_M" ;;
  *) echo "$MODELS/$pack" ;;
  esac
}
family() {
  case "$pack" in
  UD-*) echo unsloth ;;
  Coder) echo coder ;;
  Swift*) echo swift ;;
  Gyro*) echo gyro ;;
  *) echo qwen ;;
  esac
}
model_id() {
  case "$pack" in
  Coder) echo IQ1_M ;;
  *) echo "$pack" ;;
  esac
}

status() {
  local v=$(cat "$VRAM")
  echo "vram used: $((v / 1073741824)) GiB of 31.8"
  echo "ram:       $(free -g | sed -n 2p)"
  curl -s -m 2 "http://127.0.0.1:$PORT/v1/models" 2>/dev/null | head -c 160
  echo
  curl -s -m 2 http://127.0.0.1:8091/health 2>/dev/null && echo " (media model up on :8091)"
}

case "$action" in
up)
  # `max` is the system service, so the fleet and the CLI agree on one engine.
  if [ "$profile" = max ]; then
    sudo -n systemctl reset-failed strata-frontier 2>/dev/null || true
    sudo -n systemctl start strata-frontier
    echo "strata-frontier (max) starting on :$PORT"
  else
    sudo -n systemctl stop strata-frontier 2>/dev/null || true
    sudo -n systemctl reset-failed strata-frontier-alt 2>/dev/null || true
    sudo -n systemd-run --unit=strata-frontier-alt --collect -p User=llm-server -p Group=llm-server \
      -p LimitMEMLOCK=infinity -p MemoryMax=112G \
      -p Environment=HOME=/var/lib/kdn/llms/home \
      -p Environment=XDG_DATA_HOME=/var/lib/kdn/llms/models/.bench/xdg \
      -p Environment=STRATA_DATA_HOME=/var/lib/kdn/llms/models/.bench/xdg \
      -p Environment=LD_PRELOAD=/var/lib/kdn/llms/models/.bench/rocm-skip.so \
      -- /run/current-system/sw/bin/strata-serve "$profile" --port "$PORT"
    echo "strata-frontier-alt ($profile) starting on :$PORT"
  fi
  ;;
down)
  sudo -n systemctl stop strata-frontier strata-frontier-alt 2>/dev/null || true
  echo "stopped"
  ;;
status) status ;;
*)
  echo "usage: $0 {up|down|status} [--profile max|omni-max|omni-fast]" >&2
  exit 2
  ;;
esac

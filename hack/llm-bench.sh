#!/usr/bin/env bash
# Measure one served model on the brys llama-swap server.
#
# This is a measurement tool. It sends requests, reads the server timings and the
# resident child memory, and prints one TSV row per (model, step, phase). It never
# changes server state and it leaves no background process.
#
# See hack/README-llm-bench.md for the flags, the examples and the caveats.
set -eEuo pipefail

readonly PROG="${0##*/}"

MODEL=""
BASE_URL="https://brys.priv.nb.net.int.kdn.im/v1"
KEY_FILE="/tmp/opencode/brys.key"
STEPS=""
MAX_TOKENS=128
PROMPT_TOKENS=2048
SSH_HOST="kdn-brys"
JSON=0
TIMEOUT=600

usage() {
  cat <<'EOF'
Measure one served model on the brys llama-swap server.

Usage:
  llm-bench.sh --model ID [flags]

Flags:
  --model ID          The model id from GET /v1/models. Required.
  --base-url URL      OpenAI-compatible base. Default: the brys compat proxy.
  --key-file PATH     A file with the bearer key. Default: /tmp/opencode/brys.key.
  --steps LIST        A comma-separated list of steps. Default: all steps.
                      Steps: cold-start, warm-start, decode, prefill, ttft,
                      reuse, mem, faults, vram.
  --max-tokens N      The decode cap. Default: 128.
  --prompt-tokens N   The prefill target token count. Default: 2048.
  --ssh-host HOST     The ssh host for mem, faults and vram. Default: kdn-brys.
                      An empty value skips the ssh steps.
  --json              Print one JSON object per row instead of TSV.
  --timeout SECONDS   The per-request curl timeout. Default: 600.
  --help              Print this help.

Output: one TSV header, then one row per (model, step, phase) with a timestamp.

Examples:
  llm-bench.sh --model tmax-2b --steps decode,prefill
  llm-bench.sh --model tmax-2b --prompt-tokens 4096 --json
  llm-bench.sh --model frontier --steps cold-start,decode,prefill
EOF
}

die() { echo "$PROG: $*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --model) MODEL="${2:?}"; shift 2 ;;
    --base-url) BASE_URL="${2:?}"; shift 2 ;;
    --key-file) KEY_FILE="${2:?}"; shift 2 ;;
    --steps) STEPS="${2:?}"; shift 2 ;;
    --max-tokens) MAX_TOKENS="${2:?}"; shift 2 ;;
    --prompt-tokens) PROMPT_TOKENS="${2:?}"; shift 2 ;;
    --ssh-host) SSH_HOST="${2:-}"; shift 2 ;;
    --json) JSON=1; shift ;;
    --timeout) TIMEOUT="${2:?}"; shift 2 ;;
    --help | -h) usage; exit 0 ;;
    *) die "unknown flag: $1 (see --help)" ;;
  esac
done

[ -n "$MODEL" ] || { usage >&2; exit 2; }
case "$MAX_TOKENS" in '' | *[!0-9]*) die "--max-tokens must be a positive integer" ;; esac
case "$PROMPT_TOKENS" in '' | *[!0-9]*) die "--prompt-tokens must be a positive integer" ;; esac

readonly ALL_STEPS="cold-start,warm-start,decode,prefill,ttft,reuse,mem,faults,vram"
if [ -z "$STEPS" ]; then
  STEPS="$ALL_STEPS"
  # mem, faults and vram need ssh; drop them when the caller disabled ssh.
  if [ -z "$SSH_HOST" ]; then
    STEPS="cold-start,warm-start,decode,prefill,ttft,reuse"
  fi
else
  case ",$STEPS," in
    *,all,*) STEPS="$ALL_STEPS" ;;
  esac
fi

step_enabled() {
  case ",$STEPS," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

# The key is never hardcoded. Prefer the local file; read it on brys when the file is absent.
API_KEY=""
load_key() {
  if [ -s "$KEY_FILE" ]; then
    API_KEY="$(tr -d '[:space:]' <"$KEY_FILE")"
  elif [ -n "$SSH_HOST" ]; then
    API_KEY="$(ssh -o BatchMode=yes "$SSH_HOST" \
      'sudo -n cat /run/configs/llms/llama-server/api-keys/default' 2>/dev/null \
      | tr -d '[:space:]')" || true
  fi
  [ -n "$API_KEY" ] || die "no API key. Set --key-file or provide --ssh-host."
}
load_key

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; readonly TS
HOST="$(hostname)"; readonly HOST

box_note() {
  # A one-line note on the box state, so a reader can judge the run.
  local load
  if [ -n "$SSH_HOST" ]; then
    load="$(ssh -o BatchMode=yes "$SSH_HOST" 'cat /proc/loadavg' 2>/dev/null || echo '?')"
  else
    load="?"
  fi
  printf 'load=%s' "${load%% *}"
}

BOX_NOTE="$(box_note)"

# The model path reported by the server maps to the child process --model argument.
declare -A MODEL_PATH=()

fetch_model_path() {
  local id="$1" body
  body="$(curl -sS -m "$TIMEOUT" \
    -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json' \
    "$BASE_URL/chat/completions" \
    -d "{\"model\":\"$id\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":1,\"stream\":false}")" \
    || return 1
  jq -er '.model' <<<"$body" 2>/dev/null
}

model_path() {
  local id="$1"
  if [ -z "${MODEL_PATH[$id]:-}" ]; then
    MODEL_PATH[$id]="$(fetch_model_path "$id")" || return 1
  fi
  printf '%s' "${MODEL_PATH[$id]}"
}

# ---------------------------------------------------------------- output

row() {
  # row STEP PHASE KEY VALUE [UNIT]
  local step="$1" phase="$2" key="$3" value="$4" unit="${5:-}"
  if [ "$JSON" -eq 1 ]; then
    jq -cn \
      --arg ts "$TS" --arg host "$HOST" --arg model "$MODEL" \
      --arg step "$step" --arg phase "$phase" --arg key "$key" \
      --arg unit "$unit" --arg box "$BOX_NOTE" \
      --argjson value "$value" \
      '{ts:$ts,host:$host,model:$model,step:$step,phase:$phase,key:$key,value:$value,unit:$unit,box:$box}'
  else
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$TS" "$HOST" "$MODEL" "$step" "$phase" "$key" "$value" "$BOX_NOTE"
  fi
}

print_header() {
  if [ "$JSON" -eq 1 ]; then return 0; fi
  printf 'ts\thost\tmodel\tstep\tphase\tkey\tvalue\tbox_note\n'
}

# ---------------------------------------------------------------- requests

# Build a prompt of about PROMPT_TOKENS tokens. The tile repeats, so the count is
# stable. For the models on brys this English tile is about five characters per
# token, so the target length is estimated from the character count. The server
# reports the exact `prompt_n`, so the estimate only has to be close. A salt makes
# the prompt unique, which keeps it out of the server prompt cache.
build_prompt() {
  local salt="${1:-}"
  local chars=$(( PROMPT_TOKENS * 5 ))
  [ "$chars" -lt 24 ] && chars=24
  python3 -c "print('$salt' + ('bench mark token stream. ' * ($chars // 24 + 1))[:$chars])"
}

# A non-streaming decode call. Echoes the JSON body.
chat_decode() {
  local id="$1" prompt="$2"
  curl -sS -m "$TIMEOUT" \
    -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json' \
    "$BASE_URL/chat/completions" \
    -d "$(jq -cn --arg m "$id" --arg p "$prompt" --argjson n "$MAX_TOKENS" \
      '{model:$m,messages:[{role:"user",content:$p}],max_tokens:$n,stream:false}')"
}

# A streaming call. Prints the seconds to the first content chunk and the seconds to
# the end, tab-separated. The final usage chunk carries the timings.
stream_timings() {
  local id="$1" prompt="$2"
  curl -sS -N -m "$TIMEOUT" \
    -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json' \
    "$BASE_URL/chat/completions" \
    -d "$(jq -cn --arg m "$id" --arg p "$prompt" --argjson n "$MAX_TOKENS" \
      '{model:$m,messages:[{role:"user",content:$p}],max_tokens:$n,stream:true,stream_options:{include_usage:true}}')" \
    | python3 -c '
import json, sys, time
start = time.monotonic()
ttft = None
last = None
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("data:"):
        continue
    payload = line[5:].strip()
    if payload == "[DONE]":
        break
    try:
        obj = json.loads(payload)
    except ValueError:
        continue
    last = obj
    if ttft is None:
        for ch in obj.get("choices", []):
            if (ch.get("delta") or {}).get("content"):
                ttft = time.monotonic() - start
                break
end = time.monotonic() - start
timings = (last or {}).get("timings") or {}
ttft_str = "" if ttft is None else repr(ttft)
print("%s\t%s\t%s" % (ttft_str, repr(end), json.dumps(timings)))
'
}

num_or_empty() { jq -er "$1" <<<"$2" 2>/dev/null || printf ''; }

# ---------------------------------------------------------------- steps

# Time to the first streamed token. The cold phase assumes the model is not resident.
# The warm phase sends a throwaway request first, so the model is loaded and its
# weights are in page cache.
step_start() {
  local step="$1" phase="$2"
  if [ "$phase" = "warm" ]; then
    chat_decode "$MODEL" "warmup" >/dev/null
  fi
  local out ttft
  out="$(stream_timings "$MODEL" "hello")"
  ttft="$(cut -f1 <<<"$out")"
  row "$step" "$phase" "ttft_s" "${ttft:-null}"
  if [ -n "$ttft" ]; then
    row "$step" "$phase" "ttft_ms" "$(python3 -c "print(round($ttft*1000,1))")"
  fi
}

step_decode() {
  local body
  body="$(chat_decode "$MODEL" "Write one short sentence about the sea.")"
  local dps pn
  dps="$(num_or_empty '.timings.predicted_per_second' "$body")"
  pn="$(num_or_empty '.timings.predicted_n' "$body")"
  row decode run "predicted_tok_s" "${dps:-null}"
  row decode run "predicted_n" "${pn:-null}"
}

step_prefill() {
  local prompt body pps pn cn
  prompt="$(build_prompt "prefill nonce $TS $RANDOM ")"
  body="$(chat_decode "$MODEL" "$prompt")"
  pps="$(num_or_empty '.timings.prompt_per_second' "$body")"
  pn="$(num_or_empty '.timings.prompt_n' "$body")"
  cn="$(num_or_empty '.timings.cache_n' "$body")"
  row prefill run "prompt_tok_s" "${pps:-null}"
  row prefill run "prompt_n" "${pn:-null}"
  row prefill run "cache_n" "${cn:-null}"
}

step_ttft() {
  local stream_ttft nonstream_ttft
  stream_ttft="$(cut -f1 <<<"$(stream_timings "$MODEL" "hi")")"
  nonstream_ttft="$(BENCH_URL="$BASE_URL" BENCH_MODEL="$MODEL" BENCH_KEY="$API_KEY" \
    BENCH_TIMEOUT="$TIMEOUT" python3 -c '
import time, urllib.request, json, os
url = os.environ["BENCH_URL"] + "/chat/completions"
body = json.dumps({"model": os.environ["BENCH_MODEL"],
                   "messages": [{"role": "user", "content": "hi"}],
                   "max_tokens": 1, "stream": False}).encode()
req = urllib.request.Request(url, data=body,
                             headers={"Authorization": "Bearer " + os.environ["BENCH_KEY"],
                                      "Content-Type": "application/json"})
t0 = time.monotonic()
urllib.request.urlopen(req, timeout=float(os.environ["BENCH_TIMEOUT"])).read()
print(round(time.monotonic() - t0, 4))
')"
  row ttft stream "ttft_s" "${stream_ttft:-null}"
  if [ -n "$stream_ttft" ]; then
    row ttft stream "ttft_ms" "$(python3 -c "print(round($stream_ttft*1000,1))")"
  fi
  row ttft nonstream "ttft_s" "${nonstream_ttft:-null}"
}

step_reuse() {
  local prompt body1 body2 c1 c2 pps1 pps2
  prompt="$(build_prompt)"
  body1="$(chat_decode "$MODEL" "$prompt")"
  body2="$(chat_decode "$MODEL" "$prompt")"
  c1="$(num_or_empty '.timings.cache_n' "$body1")"
  c2="$(num_or_empty '.timings.cache_n' "$body2")"
  pps1="$(num_or_empty '.timings.prompt_per_second' "$body1")"
  pps2="$(num_or_empty '.timings.prompt_per_second' "$body2")"
  row reuse first "cache_n" "${c1:-null}"
  row reuse second "cache_n" "${c2:-null}"
  row reuse first "prompt_tok_s" "${pps1:-null}"
  row reuse second "prompt_tok_s" "${pps2:-null}"
}

# The model path of the resident child, then its pid. Prints the pid.
child_pid() {
  local path="$1" pid
  pid="$(ssh -o BatchMode=yes "$SSH_HOST" \
    "pgrep -f 'llama-server.*--model $path'" 2>/dev/null | head -1)" || true
  [ -n "$pid" ] || return 1
  printf '%s' "$pid"
}

step_mem() {
  local path pid status rss anon file
  path="$(model_path "$MODEL")" || { echo "$PROG: cannot resolve the model path" >&2; return 1; }
  pid="$(child_pid "$path")" || { echo "$PROG: no resident child for $path" >&2; return 1; }
  status="$(ssh -o BatchMode=yes "$SSH_HOST" "cat /proc/$pid/status" 2>/dev/null)" || return 1
  rss="$(awk '/^VmRSS:/{print $2}' <<<"$status")"
  anon="$(awk '/^RssAnon:/{print $2}' <<<"$status")"
  file="$(awk '/^RssFile:/{print $2}' <<<"$status")"
  row mem run "pid" "${pid:-null}"
  row mem run "vmrss_kb" "${rss:-null}"
  row mem run "rssanon_kb" "${anon:-null}"
  row mem run "rssfile_kb" "${file:-null}"
}

# Major fault count of the child: field 12 of /proc/<pid>/stat. The process name is
# `llama-server`, so it holds no space and field 12 is stable. The remote shell is
# fish, so the awk program uses double quotes with escaped field numbering.
read_majflt() {
  local pid="$1"
  ssh -o BatchMode=yes "$SSH_HOST" \
    "awk '{print \$12}' /proc/$pid/stat" 2>/dev/null
}

step_faults() {
  local path pid maj1 maj2 faults
  path="$(model_path "$MODEL")" || return 1
  pid="$(child_pid "$path")" || return 1
  maj1="$(read_majflt "$pid")" || return 1
  [ -n "$maj1" ] || return 1
  sleep 5
  maj2="$(read_majflt "$pid")" || return 1
  [ -n "$maj2" ] || return 1
  faults="$(python3 -c "print(round(($maj2-$maj1)/5.0,3))")"
  row faults idle "major_faults_s" "$faults"
}

# GPU VRAM of the W6600, read from sysfs over ssh. There is no amd-smi or
# rocm-smi on brys, and the box serves one model at a time, so the card-wide
# counters report the serving child. A CPU-only model leaves them near zero.
step_vram() {
  if [ -z "$SSH_HOST" ]; then
    echo "$PROG: vram needs --ssh-host; skipped" >&2
    return 0
  fi
  local raw used total
  raw="$(ssh -o BatchMode=yes "$SSH_HOST" \
    "cat /sys/class/drm/card1/device/mem_info_vram_used /sys/class/drm/card1/device/mem_info_vram_total" 2>/dev/null)" || return 1
  used="$(awk 'NR==1{print $1}' <<<"$raw")"
  total="$(awk 'NR==2{print $1}' <<<"$raw")"
  [ -n "$used" ] && [ -n "$total" ] || { echo "$PROG: cannot read VRAM from $SSH_HOST" >&2; return 1; }
  row vram run "vram_used_MiB" "$(python3 -c "print(round($used/1048576,1))")"
  row vram run "vram_total_MiB" "$(python3 -c "print(round($total/1048576,1))")"
}

# ---------------------------------------------------------------- run

print_header

if step_enabled cold-start; then step_start cold-start cold; fi
if step_enabled warm-start; then step_start warm-start warm; fi
step_enabled decode && step_decode
step_enabled prefill && step_prefill
step_enabled ttft && step_ttft
step_enabled reuse && step_reuse
step_enabled mem && step_mem
step_enabled faults && step_faults
step_enabled vram && step_vram

exit 0

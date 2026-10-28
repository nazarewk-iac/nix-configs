# Collect llama-swap's per-request performance records into a durable JSONL file and an
# optional Prometheus textfile.
#
# Why a poller and not an SSE subscriber: the `activity` event carries only `{"id": N}` (verified
# on llama-swap 249), so the record has to be read back from `/api/metrics/activity` anyway. That
# endpoint is a ring (25 records measured), so the poll interval must be short enough that a burst
# cannot roll the ring over twice between two polls. Two seconds leaves a wide margin.
#
# Facts this script relies on, all measured on brys (see
# docs/tasks/2026-10/llm-metrics-persistence/api-surface.research.md):
#   * a record carries the BASE model id, never the alias, so the alias list is resolved from
#     `/v1/models`, which is also where the routing version comes from;
#   * ids are per process, so a restart resets them; the collector detects a reset, bumps its
#     generation counter and keeps appending, so the JSONL stays unambiguous;
#   * `/api/captures/<id>` holds the bodies, but they are user data, so this script never reads them.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: llm-stats collect [OPTIONS]

  --base-url URL        llama-swap base URL (default: http://127.0.0.1:39700)
  --key-file PATH       file holding the API key (default: none, no auth header)
  --state-dir PATH      where the JSONL files live (required)
  --interval SECONDS    poll interval (default: 2)
  --keep-days DAYS      delete day files older than this (default: 90)
  --prom-textfile PATH  also write a Prometheus textfile with the latest values per model
  --once                one poll, then exit (for a test or a cron)
  -h, --help            this text
USAGE
}

main() {
  local sub="${1:-}"
  [[ $sub == "collect" ]] || {
    usage
    exit 2
  }
  shift

  local base="http://127.0.0.1:39700"
  local key_file="" state_dir="" interval=2 keep_days=90 prom_file="" once=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-url) base="$2"; shift 2 ;;
      --key-file) key_file="$2"; shift 2 ;;
      --state-dir) state_dir="$2"; shift 2 ;;
      --interval) interval="$2"; shift 2 ;;
      --keep-days) keep_days="$2"; shift 2 ;;
      --prom-textfile) prom_file="$2"; shift 2 ;;
      --once) once=1; shift ;;
      -h | --help) usage; exit 0 ;;
      *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
    esac
  done
  [[ -n $state_dir ]] || { echo "--state-dir is required" >&2; exit 2; }
  mkdir -p "$state_dir"

  local auth=()
  if [[ -n $key_file ]]; then
    local key
    key="$(head -n 1 "$key_file")"
    auth=(-H "Authorization: Bearer $key")
  fi

  local cursor_file="$state_dir/.cursor"
  local last_id=0 generation=0
  if [[ -f $cursor_file ]]; then
    # shellcheck disable=SC1090
    . "$cursor_file"
  fi

  local host
  host="$(uname -n)"

  poll_once() {
    local activity models
    activity="$(curl -sS --max-time 10 "${auth[@]}" "$base/api/metrics/activity")" || return 0
    models="$(curl -sS --max-time 10 "${auth[@]}" "$base/v1/models")" || models='{"data":[]}'

    # id -> ["alias", ...] and a version string that changes when the served set changes.
    local alias_map routing_version
    # `llama-swap` nests the alias list under `.meta.llamaswap.aliases` (verified on
    # 249); a plain top-level `.aliases` is absent, which silently produced an empty
    # map and attributed every request to a base model id. Accept both shapes.
    alias_map="$(jq -c '[.data[] | {key: .id, value: (.aliases // .meta.llamaswap.aliases // [])}] | from_entries' <<<"$models")"
    routing_version="$(jq -r '[.data[].id] | sort | join(",")' <<<"$models" | sha256sum | cut -c1-12)"

    local newest
    newest="$(jq -r '[.data[].id] | max // 0' <<<"$activity")"
    # A restart resets the id sequence, so the newest id can be below the cursor.
    if ((newest < last_id)); then
      generation=$((generation + 1))
      last_id=0
    fi

    local day_file collected_at
    day_file="$state_dir/activity-$(date -u +%F).jsonl"
    collected_at="$(date -u +%FT%TZ)"

    jq -c --argjson last "$last_id" --arg gen "$generation" --arg host "$host" \
      --arg ver "$routing_version" --arg at "$collected_at" --argjson aliases "$alias_map" '
      .data[]
      | select(.id > $last)
      | {
          ts: (.timestamp | if type == "number" then (todateiso8601) else . end),
          id,
          generation: ($gen | tonumber),
          host: $host,
          model,
          aliases: ($aliases[.model] // []),
          routing_version: $ver,
          req_path,
          status: .resp_status_code,
          content_type: .resp_content_type,
          duration_ms,
          input_tokens: .tokens.input_tokens,
          output_tokens: .tokens.output_tokens,
          cache_tokens: .tokens.cache_tokens,
          draft_tokens: .tokens.draft_tokens,
          draft_acc_tokens: .tokens.draft_acc_tokens,
          prompt_per_second: .tokens.prompt_per_second,
          tokens_per_second: .tokens.tokens_per_second,
          fifo_priority: (.metadata.fifo_priority // null),
          has_capture,
          collected_at: $at
        }' <<<"$activity" >>"$day_file"

    if ((newest > last_id)); then
      last_id=$newest
    fi
    printf 'last_id=%d\ngeneration=%d\n' "$last_id" "$generation" >"$cursor_file"

    if [[ -n $prom_file ]]; then
      # One gauge line per model, from the latest record of the ring. The values are
      # per-request, so they are exported as gauges grouped under the model id, and the set of
      # models present is the ring's, not the configured fleet's: a model that served no request
      # since the last llama-swap start has no series. That is a documented limitation.
      jq -r --argjson aliases "$alias_map" '
        [ .data[] ] | group_by(.model) | map(.[0]) | .[]
        | "llm_prompt_tokens_per_second{model=\"\(.model)\",aliases=\"\(($aliases[.model] // []) | join(","))\"} \(.tokens.prompt_per_second)",
          "llm_tokens_per_second{model=\"\(.model)\",aliases=\"\(($aliases[.model] // []) | join(","))\"} \(.tokens.tokens_per_second)",
          "llm_request_duration_ms{model=\"\(.model)\",aliases=\"\(($aliases[.model] // []) | join(","))\"} \(.duration_ms)",
          "llm_input_tokens{model=\"\(.model)\",aliases=\"\(($aliases[.model] // []) | join(","))\"} \(.tokens.input_tokens)",
          "llm_output_tokens{model=\"\(.model)\",aliases=\"\(($aliases[.model] // []) | join(","))\"} \(.tokens.output_tokens)"' <<<"$activity" \
        >"$prom_file.tmp"
      mv "$prom_file.tmp" "$prom_file"
    fi

    if ((once)); then
      return 0
    fi
    # Rotation: drop whole day files older than the retention window.
    find "$state_dir" -maxdepth 1 -name 'activity-*.jsonl' -mtime "+$keep_days" -delete 2>/dev/null || true
  }

  if ((once)); then
    poll_once
    return 0
  fi
  while true; do
    poll_once || true
    sleep "$interval"
  done
}

main "$@"

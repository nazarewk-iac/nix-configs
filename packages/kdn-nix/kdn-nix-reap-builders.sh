#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

# kdn-nix-reap-builders finds and, on request, kills STALLED builders.
#
# The leak this targets: a `nix-daemon` worker that a client left behind. It stays
# alive, holds its /nix/var/nix/temproots/<pid> file (which can list thousands of
# store paths), and pins that whole closure so `nix-store --gc` sees no garbage even
# though the client is long gone. Such a worker has no children (no build running),
# is asleep, has spent ~no CPU for a long time, and its temp-root file is old.
#
# Two modes, so you can review before acting:
#   plan   (default) print the stalled processes and what they pin; change nothing
#   apply  re-check, then SIGTERM the same set, SIGKILL stragglers, and report
#
# Only `nix-daemon` workers with a temp-root file are considered. Interactive shells,
# running builds (they have children), and anything in this invocation's own process
# ancestry are never touched.

OLDER_THAN="30m"
CPU_FLOOR=2 # CPU seconds below this counts as idle
GRACE=5

usage() {
  cat >&2 <<'EOF'
usage: kdn-nix-reap-builders [MODE] [OPTIONS]

MODE:
  plan    (default) list stalled nix-daemon temp-root holders, kill nothing
  apply   kill the same set (SIGTERM, then SIGKILL after a grace period)

OPTIONS:
  -t, --older-than DURATION  minimum age since the temp-root file was written
                             (default 30m; suffixes s/m/h/d)
  -c, --cpu-floor SECONDS    CPU time below this counts as idle (default 2)
  -g, --grace SECONDS        wait after SIGTERM before SIGKILL (default 5)
  -h, --help                 show this help

After apply, run `kdn-nix-collect-garbage` to free the newly unreachable paths.
EOF
}

to_secs() {
  case "$1" in
  *s) printf '%s' "${1%s}" ;;
  *m) printf '%s' "$((${1%m} * 60))" ;;
  *h) printf '%s' "$((${1%h} * 3600))" ;;
  *d) printf '%s' "$((${1%d} * 86400))" ;;
  '') printf '0' ;;
  *) printf '%s' "$1" ;;
  esac
}

mode="plan"
while [[ $# -gt 0 ]]; do
  case "$1" in
  plan | apply)
    mode="$1"
    shift
    ;;
  -t | --older-than)
    OLDER_THAN="$2"
    shift 2
    ;;
  --older-than=*)
    OLDER_THAN="${1#*=}"
    shift
    ;;
  -c | --cpu-floor)
    CPU_FLOOR="$2"
    shift 2
    ;;
  -g | --grace)
    GRACE="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "unknown argument: $1" >&2
    usage
    exit 2
    ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "restarting as root..." >&2
  exec sudo "$BASH" "$0" "$@"
fi

THRESH="$(to_secs "$OLDER_THAN")"

log() { printf "$1: %s\n" "${@:2}"; }

# ppid reads the parent PID from /proc/<pid>/stat. The comm field may contain
# spaces and parens, so strip through the last ')' first.
ppid() {
  local s
  s="$(cat "/proc/$1/stat" 2>/dev/null)" || return 0
  s="${s##*) }"
  awk '{print $2}' <<<"$s"
}

# Build the set of PIDs never to kill: this script and its ancestors.
declare -A ANCESTRY=()
p=$$
while [[ -n "$p" && "$p" != "0" ]]; do
  ANCESTRY[$p]=1
  p="$(ppid "$p")"
done

# cpu_ticks prints utime+stime in clock ticks from /proc/<pid>/stat (fields 14,15).
cpu_ticks() { awk '{print $14 + $15}' "/proc/$1/stat" 2>/dev/null || echo 0; }

# collect fills CAND[] with candidate info lines for stalled nix-daemon workers.
declare -a CAND=()
collect() {
  local pid comm stat etimes cputimes tr
  while read -r pid comm stat etimes cputimes; do
    [[ -n "${ANCESTRY[$pid]:-}" ]] && continue
    [[ "$comm" == nix-daemon* ]] || continue
    # asleep only: never touch running (R), uninterruptible IO (D) or zombie (Z)
    [[ "$stat" == R* || "$stat" == *D* || "$stat" == *Z* ]] && continue
    ((etimes >= THRESH)) || continue
    ((cputimes <= CPU_FLOOR)) || continue
    [[ -z "$(pgrep -P "$pid" 2>/dev/null || true)" ]] || continue
    tr="/nix/var/nix/temproots/$pid"
    [[ -e "$tr" ]] || continue
    CAND+=("$pid|$comm|$etimes|$cputimes|$tr")
  done < <(ps -eo pid=,comm=,stat=,etimes=,cputimes=)
}

# Drop candidates whose CPU advanced over a short sample (i.e. actually working).
settle_filter() {
  [[ ${#CAND[@]} -gt 0 ]] || return 0
  declare -A before=()
  local c pid
  for c in "${CAND[@]}"; do
    pid="${c%%|*}"
    before[$pid]="$(cpu_ticks "$pid")"
  done
  sleep 2
  local kept=()
  for c in "${CAND[@]}"; do
    pid="${c%%|*}"
    if [[ "$(cpu_ticks "$pid")" == "${before[$pid]}" ]]; then
      kept+=("$c")
    fi
  done
  CAND=("${kept[@]}")
}

print_plan() {
  local tr paths size since pid comm etimes cputimes
  printf '%-8s %-12s %8s %8s %10s %8s  %s\n' PID COMMAND AGE_S CPU_S TROOT_MB PATHS SINCE
  for c in "${CAND[@]}"; do
    IFS='|' read -r pid comm etimes cputimes tr <<<"$c"
    paths=0
    size=$((($(stat -c '%s' "$tr" 2>/dev/null || echo 0)) / 1048576))
    paths=$(grep -c . "$tr" 2>/dev/null || echo 0)
    since=$(date -d "@$(stat -c '%Y' "$tr" 2>/dev/null || date +%s)" '+%Y-%m-%d %H:%M')
    printf '%-8s %-12s %8s %8s %10s %8s  %s\n' "$pid" "$comm" "$etimes" "$cputimes" "$size" "$paths" "$since"
  done
}

apply_plan() {
  local tr pid comm etimes cputimes
  local -a term=()
  for c in "${CAND[@]}"; do
    IFS='|' read -r pid comm etimes cputimes tr <<<"$c"
    log info "[KILL   ] pid=${pid} ${comm} age=${etimes}s cpu=${cputimes}s $(grep -c . "$tr" 2>/dev/null || echo 0) paths pinned"
    term+=("$pid")
  done
  [[ ${#term[@]} -gt 0 ]] || return 0
  kill -TERM "${term[@]}" 2>/dev/null || true
  local waited=0
  while ((waited < GRACE)); do
    local alive=0
    for pid in "${term[@]}"; do
      kill -0 "$pid" 2>/dev/null && ((alive += 1))
    done
    ((alive == 0)) && break
    sleep 1
    ((waited += 1))
  done
  for pid in "${term[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      log warn "[KILL   ] pid=${pid} ignored SIGTERM, sending SIGKILL"
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done
  log info "[SUMMARY] sent signals to ${#term[@]} stalled worker(s)"
}

main() {
  log info "[CONF   ] mode=${mode} older-than=${OLDER_THAN}(${THRESH}s) cpu-floor=${CPU_FLOOR}s"
  collect
  settle_filter
  if [[ ${#CAND[@]} -eq 0 ]]; then
    log info "[RESULT ] no stalled builders found"
    return 0
  fi
  if [[ "$mode" == "plan" ]]; then
    print_plan
    log info "[RESULT ] ${#CAND[@]} stalled worker(s) found; re-run with 'apply' to kill them"
  else
    apply_plan
    log info "[RESULT ] run 'kdn-nix-collect-garbage' to free the newly unreachable paths"
  fi
}

main

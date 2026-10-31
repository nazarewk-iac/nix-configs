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
# Two modes, and apply does NOT rescan: it acts only on a plan you already saw.
#   plan   (default) scan, print the stalled processes, and WRITE the plan to a file
#   apply  read that pre-existing plan file and kill exactly those PIDs, after
#          re-checking each one still matches (guards against PID reuse)
#
# Only `nix-daemon` workers with a temp-root file are considered. Interactive shells,
# running builds (they have children), and anything in this invocation's own process
# ancestry are never touched.

MODE="plan"
PLAN_FILE="/var/tmp/kdn-nix-reap-builders.plan"
OLDER_THAN="30m"
# A worker counts as idle when its CPU use does NOT advance over the re-sample window below. The
# lifetime total is NOT a useful test: a worker that finished a build hours ago has a large total
# yet is idle now. So `--cpu-floor` is a DELTA over `--sample-seconds`.
CPU_FLOOR=0
GRACE=5
SAMPLE_SECONDS=3

usage() {
  cat >&2 <<EOF
usage: kdn-nix-reap-builders [MODE] [OPTIONS]

MODE:
  plan    (default) scan, print, and write the plan to --plan-file
  apply   kill exactly the PIDs recorded in --plan-file (must already exist)

OPTIONS:
  -f, --plan-file PATH       plan file to write (plan) or read (apply)
                             (default ${PLAN_FILE})
  -t, --older-than DURATION  plan: minimum age since the temp-root file was written
                             (default 30m; suffixes s/m/h/d)
  -c, --cpu-floor DELTA      plan: max CPU ticks gained over the sample window to still count
                             as idle (default 0 = no CPU used at all)
  -g, --grace SECONDS        apply: wait after SIGTERM before SIGKILL (default 5)
  -h, --help                 show this help

apply refuses to run without a pre-existing plan file produced by 'plan'. After
apply, run 'kdn-nix-collect-garbage' to free the newly unreachable paths.
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

if [[ $EUID -ne 0 ]]; then
  echo "restarting as root..." >&2
  exec sudo "$BASH" "$0" "$@"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
  plan | apply)
    MODE="$1"
    shift
    ;;
  -f | --plan-file)
    PLAN_FILE="$2"
    shift 2
    ;;
  --plan-file=*)
    PLAN_FILE="${1#*=}"
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
  -w | --sample-seconds)
    SAMPLE_SECONDS="$2"
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

THRESH="$(to_secs "$OLDER_THAN")"
log() { printf "$1: %s\n" "${@:2}"; }

# read_stat strips the leading "pid (comm) " (comm may hold spaces and parens) and
# prints the remaining /proc/<pid>/stat fields, so $1=state, $2=ppid, $20=starttime,
# $12+$13=utime+stime.
read_stat() {
  local s
  s="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
  printf '%s\n' "${s##*) }"
}
ppid() { read_stat "$1" | awk '{print $2}'; }
starttime() { read_stat "$1" | awk '{print $20}'; }
cpu_ticks() {
  read_stat "$1" | awk '{print $12 + $13}' || printf '0'
}
state_of() { read_stat "$1" | awk '{print $1}'; }

# PIDs never to kill: this script and its ancestors.
declare -A ANCESTRY=()
p=$$
while [[ -n "$p" && "$p" != "0" ]]; do
  ANCESTRY[$p]=1
  p="$(ppid "$p")" || break
done

# matches_signature reports whether <pid> is still a stalled nix-daemon worker that
# holds a temp-root file. STIME is the start time recorded at plan time, used to
# detect PID reuse; pass an empty STIME to skip that check.
matches_signature() {
  local pid="$1" stime="$2"
  [[ -e "/proc/$pid" ]] || return 1
  [[ -n "${ANCESTRY[$pid]:-}" ]] && return 1
  [[ "$(cat "/proc/$pid/comm" 2>/dev/null)" == nix-daemon* ]] || return 1
  case "$(state_of "$pid")" in
  R* | *D* | *Z*) return 1 ;;
  esac
  [[ -n "$(pgrep -P "$pid" 2>/dev/null || true)" ]] && return 1
  [[ -e "/nix/var/nix/temproots/$pid" ]] || return 1
  if [[ -n "$stime" && "$(starttime "$pid")" != "$stime" ]]; then
    return 1 # PID was reused by a different process
  fi
  return 0
}

# ---------------------------------------------------------------- plan
plan() {
  local pid comm stat etimes cputimes tr
  local -a rows=()
  local -A before=()
  while read -r pid comm stat etimes cputimes; do
    [[ -n "${ANCESTRY[$pid]:-}" ]] && continue
    [[ "$comm" == nix-daemon* ]] || continue
    [[ "$stat" == R* || "$stat" == *D* || "$stat" == *Z* ]] && continue
    ((etimes >= THRESH)) || continue
    [[ -z "$(pgrep -P "$pid" 2>/dev/null || true)" ]] || continue
    tr="/nix/var/nix/temproots/$pid"
    [[ -e "$tr" ]] || continue
    rows+=("$pid|$comm|$etimes|$cputimes")
    before[$pid]="$(cpu_ticks "$pid")"
  done < <(ps -eo pid=,comm=,stat=,etimes=,cputimes=)

  # Re-sample CPU over the window; keep only those whose CPU did not advance beyond --cpu-floor.
  # This is the idle test that matters: a finished build has a large lifetime total yet is idle now.
  if [[ ${#rows[@]} -gt 0 ]]; then
    sleep "$SAMPLE_SECONDS"
    local -a kept=()
    local row
    for row in "${rows[@]}"; do
      pid="${row%%|*}"
      delta=$(( $(cpu_ticks "$pid") - ${before[$pid]:-0} ))
      ((delta <= CPU_FLOOR)) && kept+=("$row")
    done
    rows=("${kept[@]}")
  fi

  {
    printf '# kdn-nix-reap-builders plan %s older-than=%s cpu-floor=%s\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$OLDER_THAN" "$CPU_FLOOR"
    printf '# pid\tstarttime\ttemproots\n'
    for row in "${rows[@]}"; do
      IFS='|' read -r pid comm etimes cputimes <<<"$row"
      printf '%s\t%s\t%s\n' "$pid" "$(starttime "$pid")" "/nix/var/nix/temproots/$pid"
    done
  } >"$PLAN_FILE"

  if [[ ${#rows[@]} -eq 0 ]]; then
    log info "[RESULT ] no stalled builders found (empty plan written to ${PLAN_FILE})"
    return 0
  fi
  printf '%-8s %-12s %8s %8s %8s  %s\n' PID COMMAND AGE_S CPU_S PATHS SINCE
  for row in "${rows[@]}"; do
    IFS='|' read -r pid comm etimes cputimes <<<"$row"
    tr="/nix/var/nix/temproots/$pid"
    local paths since
    paths="$(grep -c . "$tr" 2>/dev/null)" || paths=0
    since="$(date -d "@$(stat -c '%Y' "$tr" 2>/dev/null || date +%s)" '+%Y-%m-%d %H:%M')"
    printf '%-8s %-12s %8s %8s %8s  %s\n' "$pid" "$comm" "$etimes" "$cputimes" "$paths" "$since"
  done
  log info "[RESULT ] ${#rows[@]} stalled worker(s) written to ${PLAN_FILE}; run 'apply' to kill them"
}

# ---------------------------------------------------------------- apply
apply() {
  [[ -e "$PLAN_FILE" ]] || {
    log warn "[ERROR  ] plan file '${PLAN_FILE}' does not exist; run 'plan' first"
    exit 2
  }
  local -a term=()
  local pid stime tr
  while IFS=$'\t' read -r pid stime tr; do
    [[ -z "$pid" || "$pid" == \#* ]] && continue
    if matches_signature "$pid" "$stime"; then
      local paths
      paths="$(grep -c . "$tr" 2>/dev/null)" || paths=0
      log info "[KILL   ] pid=${pid} $(cat "/proc/$pid/comm") paths pinned=${paths}"
      term+=("$pid")
    else
      log warn "[SKIP   ] pid=${pid} no longer matches (gone, reused, busy, or not a stalled daemon)"
    fi
  done <"$PLAN_FILE"

  [[ ${#term[@]} -gt 0 ]] || {
    log info "[RESULT ] nothing to kill from ${PLAN_FILE}"
    return 0
  }

  kill -TERM "${term[@]}" 2>/dev/null || true
  local waited=0 alive
  while ((waited < GRACE)); do
    alive=0
    for pid in "${term[@]}"; do kill -0 "$pid" 2>/dev/null && ((alive += 1)); done
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
  log info "[RESULT ] signalled ${#term[@]} worker(s); run 'kdn-nix-collect-garbage' to free the paths"
}

log info "[CONF   ] mode=${MODE} plan-file=${PLAN_FILE}"
case "$MODE" in
plan) plan ;;
apply) apply ;;
esac

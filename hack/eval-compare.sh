#!/usr/bin/env bash
# The parity-gated A/B evaluation comparison of the two module trees.
#
# It compares ONE host, evaluated two ways: through `modules/universal` and through
# `modules/den/aspects`. It holds every constant that
# ../docs/tasks/2026-09/eval-performance/research.md § "Part 3" names, and it prints three figures
# and no verdict.
#
# DO NOT RUN THIS UNTIL THE TWO TREES REACH FEATURE PARITY. A run before parity compares a
# complete tree against an incomplete one, and the incomplete tree wins for the wrong reason. The
# `generalization` umbrella task tracks the parity state. The script refuses to run without
# `--parity-confirmed` for exactly that reason.
#
# Usage:
#   hack/eval-compare.sh --parity-confirmed \
#     --a '.#darwinConfigurations.anji.config.system.build.toplevel.drvPath' \
#     --b '.#denConfigurations.<entity>.config.system.build.toplevel.drvPath' \
#     [--options-a '.#darwinConfigurations.anji.options'] \
#     [--options-b '.#denConfigurations.<entity>.options']
#
# Environment:
#   KDN_EVAL_RUNS      measured runs per side, default 5.
#   KDN_EVAL_LOAD_MAX  the one-minute load ceiling, default 2.0.
#   KDN_EVAL_FORCE     non-empty skips the load gate.
#
# Output: .cache/eval-compare/<UTC stamp>/. `.gitignore` ignores `/.cache/`.
#
# THIS IS A MEASUREMENT TOOL. It never activates a system, and it never writes a lock file.
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"

PARITY=""
A_ATTR=""
B_ATTR=""
A_OPTS=""
B_OPTS=""
while [ "$#" -gt 0 ]; do
  case "$1" in
  --parity-confirmed) PARITY=1 ;;
  --a)
    A_ATTR="$2"
    shift
    ;;
  --b)
    B_ATTR="$2"
    shift
    ;;
  --options-a)
    A_OPTS="$2"
    shift
    ;;
  --options-b)
    B_OPTS="$2"
    shift
    ;;
  *)
    echo "unknown argument: $1" >&2
    exit 64
    ;;
  esac
  shift
done

if [ -z "$PARITY" ]; then
  cat >&2 <<'EOF'
BLOCKED  the two module trees are not at feature parity.

A run now compares a complete tree against an incomplete one, and the incomplete tree wins
because it does less work, not because it is faster.

Read docs/tasks/2026-09/eval-performance/research.md § "The parity confound" and check the
parity state in docs/tasks/2026-09/generalization/definition.md. Then pass --parity-confirmed.
EOF
  exit 2
fi

if [ -z "$A_ATTR" ] || [ -z "$B_ATTR" ]; then
  echo "FAIL  pass both --a and --b" >&2
  exit 64
fi

RUNS="${KDN_EVAL_RUNS:-5}"
LOAD_MAX="${KDN_EVAL_LOAD_MAX:-2.0}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$REPO/.cache/eval-compare/$STAMP"
mkdir -p "$OUT"

# ---------------------------------------------------------------- the guards

hash_locks() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 flake.lock devenv.lock
  else
    sha256sum flake.lock devenv.lock
  fi
}
hash_locks >"$OUT/locks-before.txt"
check_locks() {
  hash_locks >"$OUT/locks-after.txt"
  if ! diff -u "$OUT/locks-before.txt" "$OUT/locks-after.txt" >"$OUT/locks-diff.txt"; then
    echo "FAIL  a lock file changed during the run — see $OUT/locks-diff.txt" >&2
    return 1
  fi
  rm -f "$OUT/locks-diff.txt"
}
trap check_locks EXIT

load_now() { uptime | sed -E 's/.*load average[s]?: *//' | tr -d ',' | awk '{print $1}'; }
gate_load() {
  local now
  now="$(load_now)"
  echo "one-minute load: $now (ceiling $LOAD_MAX)"
  if [ -z "${KDN_EVAL_FORCE:-}" ] && awk -v a="$now" -v b="$LOAD_MAX" 'BEGIN { exit !(a > b) }'; then
    echo "FAIL  the machine is loaded. Wait, or set KDN_EVAL_FORCE=1." >&2
    exit 1
  fi
}
gate_load

# One pinned revision for the whole batch. It fixes the tree AND both lock files, so no flake
# update can slip between the two halves.
REV="$(jj --config signing.behavior=drop log -r '@' --no-graph -T 'commit_id')"
pin() { echo "git+file://$REPO?rev=$REV#${1#*#}"; }

A_PIN="$(pin "$A_ATTR")"
B_PIN="$(pin "$B_ATTR")"

{
  echo "stamp:     $STAMP"
  echo "revision:  $REV"
  echo "A:         $A_ATTR"
  echo "B:         $B_ATTR"
  echo "runs:      $RUNS per side, interleaved"
  echo "platform:  $(uname -srm)"
  echo "evaluator: $(nix --version)"
} | tee "$OUT/meta.txt"

# ---------------------------------------------------------------- the series

# `/usr/bin/time -p` is POSIX, so it prints `real`, `user` and `sys` in seconds on macOS and on
# Linux alike. Peak RSS needs a platform flag, so one extra run per side collects it below.
one_run() {
  local pinned="$1" out="$2"
  shift 2
  /usr/bin/time -p nix eval --no-eval-cache "$@" --raw "$pinned" >/dev/null 2>"$out"
}

field() { awk -v k="$1" '$1 == k { print $2 }' "$2"; }

median() {
  sort -n "$1" | awk '{ a[NR] = $1 } END {
    if (NR == 0) { print "n/a" }
    else if (NR % 2) { print a[(NR + 1) / 2] }
    else { printf "%.2f\n", (a[NR / 2] + a[NR / 2 + 1]) / 2 }
  }'
}
lo() { sort -n "$1" | head -1; }
hi() { sort -n "$1" | tail -1; }

for series in plain readonly; do
  extra=()
  if [ "$series" = readonly ]; then
    extra=(--read-only)
  fi

  # One discard run per side warms the page cache. research.md rows 2 and 3 show a 16 s penalty
  # without it. Throw both away.
  echo "[$series] discard runs"
  one_run "$A_PIN" "$OUT/discard-a-$series.txt" "${extra[@]}"
  one_run "$B_PIN" "$OUT/discard-b-$series.txt" "${extra[@]}"

  : >"$OUT/$series-a-real.txt"
  : >"$OUT/$series-b-real.txt"
  : >"$OUT/$series-a-user.txt"
  : >"$OUT/$series-b-user.txt"

  # Interleave A-B-A-B, never five A then five B. An interleave defends against machine drift,
  # for example thermal throttling or a background build that starts mid-batch.
  i=1
  while [ "$i" -le "$RUNS" ]; do
    echo "[$series] run $i of $RUNS"
    one_run "$A_PIN" "$OUT/$series-a-$i.txt" "${extra[@]}"
    field real "$OUT/$series-a-$i.txt" >>"$OUT/$series-a-real.txt"
    field user "$OUT/$series-a-$i.txt" >>"$OUT/$series-a-user.txt"
    one_run "$B_PIN" "$OUT/$series-b-$i.txt" "${extra[@]}"
    field real "$OUT/$series-b-$i.txt" >>"$OUT/$series-b-real.txt"
    field user "$OUT/$series-b-$i.txt" >>"$OUT/$series-b-user.txt"
    i=$((i + 1))
  done
  gate_load
done

# ---------------------------------------------------------------- peak RSS, one run per side

case "$(uname -s)" in
Darwin) TIMER=(/usr/bin/time -l) ;;
*) TIMER=(/usr/bin/time -v) ;;
esac
for side in a b; do
  pinned="$A_PIN"
  [ "$side" = b ] && pinned="$B_PIN"
  "${TIMER[@]}" nix eval --no-eval-cache --raw "$pinned" >/dev/null 2>"$OUT/rss-$side.txt"
done

# ---------------------------------------------------------------- the counters

# The deterministic counters are the PRIMARY evidence, not the clock. research.md measured
# 27,526,141 function calls in three separate runs while the wall clock moved 25 %. So one run
# each is enough.
for side in a b; do
  pinned="$A_PIN"
  [ "$side" = b ] && pinned="$B_PIN"
  NIX_SHOW_STATS=1 NIX_COUNT_CALLS=1 NIX_SHOW_STATS_PATH="$OUT/stats-$side.json" \
    nix eval --no-eval-cache --raw "$pinned" >/dev/null 2>&1
  jq 'del(.functions, .primops, .attributes)' "$OUT/stats-$side.json" >"$OUT/stats-$side-summary.json"
done

# ---------------------------------------------------------------- the work denominator

# The parity confound: a tree that implements less evaluates less, and it "wins" while doing
# nothing better. So report `cpuTime` per 1000 declared option leaves next to the raw figure.
#
# The walk forces the option tree and no option VALUE, so it cannot throw on a missing default.
# It skips every name that starts with `_`, which drops `_module`.
#
# The block below is NIX source text, not shell text. `${n}` is a Nix interpolation, and the shell
# must never expand it. So SC2016 is a false positive here.
# shellcheck disable=SC2016
LEAF_EXPR='opts:
  let
    hidden = n: builtins.substring 0 1 n == "_";
    count = o:
      if !(builtins.isAttrs o) then 0
      else if (o._type or "") == "option" then 1
      else builtins.foldl'"'"' (acc: n: acc + count o.${n}) 0
             (builtins.filter (n: !(hidden n)) (builtins.attrNames o));
  in count opts'

leaf_count() {
  local attr="$1"
  if [ -z "$attr" ]; then
    echo "n/a"
    return 0
  fi
  nix eval --no-eval-cache --json "$(pin "$attr")" --apply "$LEAF_EXPR" 2>/dev/null || echo "n/a"
}
A_LEAVES="$(leaf_count "$A_OPTS")"
B_LEAVES="$(leaf_count "$B_OPTS")"

# ---------------------------------------------------------------- the report

report_side() {
  local label="$1" side="$2" leaves="$3"
  local cpu calls thunks avoided copied
  cpu="$(jq -r '.cpuTime' "$OUT/stats-$side-summary.json")"
  calls="$(jq -r '.nrFunctionCalls' "$OUT/stats-$side-summary.json")"
  thunks="$(jq -r '.nrThunks' "$OUT/stats-$side-summary.json")"
  avoided="$(jq -r '.nrAvoided' "$OUT/stats-$side-summary.json")"
  copied="$(jq -r '.nrOpUpdateValuesCopied' "$OUT/stats-$side-summary.json")"
  echo "--- $label"
  for series in plain readonly; do
    printf '  %-9s wall median %s s  range %s .. %s s   user median %s s\n' \
      "$series" \
      "$(median "$OUT/$series-$side-real.txt")" \
      "$(lo "$OUT/$series-$side-real.txt")" \
      "$(hi "$OUT/$series-$side-real.txt")" \
      "$(median "$OUT/$series-$side-user.txt")"
  done
  echo "  cpuTime                 $cpu"
  echo "  nrFunctionCalls         $calls"
  echo "  nrThunks / nrAvoided    $thunks / $avoided"
  echo "  nrOpUpdateValuesCopied  $copied"
  echo "  option leaves           $leaves"
  if [ "$leaves" != "n/a" ] && [ "$leaves" -gt 0 ] 2>/dev/null; then
    awk -v c="$cpu" -v l="$leaves" 'BEGIN { printf "  cpuTime per 1000 leaves %.3f\n", 1000 * c / l }'
  fi
}

{
  echo
  echo "=== the three figures. This script prints NO verdict. ==="
  report_side "A — $A_ATTR" a "$A_LEAVES"
  report_side "B — $B_ATTR" b "$B_LEAVES"
  cat <<'EOF'

Read it with these five rules:

1. A wall-clock win with NO nrFunctionCalls win is machine noise, not a real win.
2. A tree that is genuinely faster wins on `cpuTime per 1000 leaves` as well. A tree that only
   implements less wins on the raw figure and ties or loses on the normalised one.
3. Both trees own about 0.5 % of evaluation self time, and the extra nixpkgs copies own about
   16.8 % (research.md § "Grouped by source tree"). A tree cannot win more than it spends.
4. Count the distinct nixpkgs source roots per side before you conclude anything. Run
   `hack/eval-profile.sh` on each attribute and read its "SELF TIME by source root" table.
5. Count the nested evaluations per side by hand. `modules/meta/default.nix:28` runs a nested
   `lib.evalModules`, and `nix-rosetta-builder` runs a nested `nixosSystem`. No cheap probe exists.
EOF
  echo
  echo "raw series, counters and peak RSS: $OUT"
} | tee "$OUT/report.txt"

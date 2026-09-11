#!/usr/bin/env bash
# Reproduce one Nix evaluation profile of this repository.
#
# The system evaluator is Lix, and Lix 2.95.2 ships no flamegraph profiler. So this script fetches
# a CppNix client — about 1.5 MiB — and profiles with that client against the Lix daemon. The store
# protocol matches and the client stays trusted. See
# ../docs/tasks/2026-09/eval-performance/research.md § "The CppNix-client-on-Lix-daemon experiment".
#
# THIS IS A MEASUREMENT TOOL. It never activates a system, and it never writes a lock file.
#
# Read one limit before you quote a number: the profile describes CppNix, not Lix. A relative
# conclusion transfers to Lix when the cost sits in Nix code. An absolute second count does not.
#
# Usage:
#   hack/eval-profile.sh                                  # host anji, the default attribute
#   hack/eval-profile.sh '.#nixosConfigurations.brys.config.system.build.toplevel.drvPath'
#   KDN_EVAL_READ_ONLY=1 hack/eval-profile.sh             # pure evaluation, no .drv instantiation
#   KDN_EVAL_FORCE=1 hack/eval-profile.sh                 # run even on a loaded machine
#
# Environment:
#   KDN_EVAL_READ_ONLY   non-empty adds `--read-only`. It cuts a Lix run from 64.07 s to 23.35 s
#                        (research.md timing table, rows 3 and 5), because it skips instantiation.
#   KDN_EVAL_HZ          the sample rate, default 99. Keep 99: a 999 Hz run wrote 184 MB against
#                        33 MB and added no detail (research.md § "Overhead of the profiler").
#   KDN_EVAL_LOAD_MAX    the one-minute load ceiling, default 2.0.
#   KDN_EVAL_FORCE       non-empty skips the load gate.
#   KDN_EVAL_CPP_ATTR    the CppNix client, default `nixpkgs#nixVersions.latest`.
#   KDN_EVAL_FG_ATTR     the renderer, default `nixpkgs#flamegraph`.
#
# Output: .cache/eval-profile/<UTC stamp>/. `.gitignore` ignores `/.cache/`, so nothing here
# reaches a commit. The artefacts stay ephemeral on purpose: a `.folded` file reaches 33 MB, and
# one profile is valid for exactly one revision, one machine and one evaluator. Paste the ranked
# table into the task's `.worklog.md` when a number matters.
#
# It needs: nix, jj, python3, and one network round trip on the first run.
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
cd "$REPO"

ATTR="${1:-.#darwinConfigurations.anji.config.system.build.toplevel.drvPath}"
HZ="${KDN_EVAL_HZ:-99}"
CPP_ATTR="${KDN_EVAL_CPP_ATTR:-nixpkgs#nixVersions.latest}"
FG_ATTR="${KDN_EVAL_FG_ATTR:-nixpkgs#flamegraph}"
LOAD_MAX="${KDN_EVAL_LOAD_MAX:-2.0}"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$REPO/.cache/eval-profile/$STAMP"
mkdir -p "$OUT"

# ---------------------------------------------------------------- the four guards

# Guard 1 — the lock files. `nix run '.#update'` is the only thing that may move them. A silent
# rewrite from a measurement is unrecoverable in a fork repository, so hash them and check again.
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

# Guard 2 — the machine load. A measurement on a loaded machine is worthless.
LOAD1="$(uptime | sed -E 's/.*load average[s]?: *//' | tr -d ',' | awk '{print $1}')"
echo "one-minute load: $LOAD1 (ceiling $LOAD_MAX)"
if [ -z "${KDN_EVAL_FORCE:-}" ] && awk -v a="$LOAD1" -v b="$LOAD_MAX" 'BEGIN { exit !(a > b) }'; then
  echo "FAIL  the machine is loaded. Wait, or set KDN_EVAL_FORCE=1." >&2
  exit 1
fi

# Guard 3 — a pinned revision. A dirty `git+file:` tree gets hashed twice, and the two hashes
# disagree when another writer edits a tracked file. That fails the evaluation part way. See
# research.md § "One real hazard did fire".
REV="$(jj --config signing.behavior=drop log -r '@' --no-graph -T 'commit_id')"
PINNED="git+file://$REPO?rev=$REV#${ATTR#*#}"

# Guard 4 — the evaluation cache. Nix caches a failure and replays it in under a second, so a
# sub-second result is almost always a stale entry. See ../checks/README.md § "When a check fails".
COMMON=(--no-eval-cache)

RO=()
if [ -n "${KDN_EVAL_READ_ONLY:-}" ]; then
  RO=(--read-only)
fi

case "$(uname -s)" in
Darwin) TIMER=(/usr/bin/time -l) ;;
*) TIMER=(/usr/bin/time -v) ;;
esac

# ---------------------------------------------------------------- the tools

echo "fetching the CppNix client and the renderer (about 1.6 MiB)"
CPP="$(nix build --no-link --print-out-paths "$CPP_ATTR" | grep -v -- '-man' | head -1)"
FG="$(nix build --no-link --print-out-paths "$FG_ATTR" | head -1)"

{
  echo "stamp:       $STAMP"
  echo "attribute:   $ATTR"
  echo "pinned:      $PINNED"
  echo "revision:    $REV"
  echo "read-only:   ${KDN_EVAL_READ_ONLY:-no}"
  echo "sample rate: $HZ Hz"
  echo "load before: $LOAD1"
  echo "platform:    $(uname -srm)"
  echo "lix:         $(nix --version)"
  echo "cppnix:      $("$CPP/bin/nix" --version)"
} | tee "$OUT/meta.txt"

# ---------------------------------------------------------------- the profile

echo "profiling with the CppNix client"
"${TIMER[@]}" "$CPP/bin/nix" eval \
  --no-write-lock-file --no-update-lock-file --offline \
  "${COMMON[@]}" "${RO[@]}" \
  --option eval-profiler flamegraph \
  --option eval-profile-file "$OUT/profile.folded" \
  --option eval-profiler-frequency "$HZ" \
  --raw "$PINNED" \
  >"$OUT/result-cppnix.txt" 2>"$OUT/time-cppnix.txt"

echo "rendering the flamegraph"
"$FG/bin/flamegraph.pl" --countname samples --width 1800 \
  "$OUT/profile.folded" >"$OUT/profile.svg"

echo "ranking the cost centres"
python3 "$REPO/hack/eval-profile-rank.py" "$OUT/profile.folded" >"$OUT/rank.txt"

# ---------------------------------------------------------------- the Lix cross-check

# The counters are deterministic: identical inputs give an identical `nrFunctionCalls`. They cost
# 0.1 % of wall clock, so they always run. They report a call count and never a self time, so they
# cross-check the ranking of the profile and never replace it.
echo "cross-checking with the Lix counters"
NIX_SHOW_STATS=1 NIX_COUNT_CALLS=1 NIX_SHOW_STATS_PATH="$OUT/stats.json" \
  "${TIMER[@]}" nix eval "${COMMON[@]}" "${RO[@]}" \
  --raw "$PINNED" \
  >"$OUT/result-lix.txt" 2>"$OUT/time-lix.txt"

jq 'del(.functions, .primops, .attributes)' "$OUT/stats.json" >"$OUT/stats-summary.json"

# ---------------------------------------------------------------- the report

echo
sed -n '1,40p' "$OUT/rank.txt"
echo
echo "wrote:"
echo "  $OUT/rank.txt            the four ranked tables"
echo "  $OUT/profile.svg         the flamegraph"
echo "  $OUT/profile.folded      the raw collapsed stacks"
echo "  $OUT/stats-summary.json  the Lix counters, without the per-function arrays"
echo "  $OUT/meta.txt            the revision, both evaluator versions and the load"
echo
echo "Open the SVG, or drop profile.folded into https://speedscope.app/ and use the Sandwich View."

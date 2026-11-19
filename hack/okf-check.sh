#!/usr/bin/env bash
# Run every OKF gate on a bundle in the working tree.
#
# The Nix checks (`okf-memory-validate`, `ai-xf-validate`, `okf-rs-check`, `okflint-validate`,
# `okph-validate`) run the same gates on a sandbox copy. This script is the authoring loop: it
# reads the files as they are, so a fix is one edit away.
#
# By default every gate runs and every failure is reported. `--fail-fast` stops at the first one.
#
# Usage:
#   nix run .#okf-check [-- --fail-fast] [bundle]
#   hack/okf-check.sh [--fail-fast] [bundle]
set -uo pipefail

usage() {
  cat <<'EOF'
usage: okf-check [--fail-fast] [bundle]

Run every OKF gate on a bundle in the working tree.

  --fail-fast, -x   stop at the first failing gate
  -h, --help        show this help

The default bundle is .agents/knowledge in the repository root.
EOF
}

fail_fast=false
positional=()
for arg in "$@"; do
  case "$arg" in
  --fail-fast | -x) fail_fast=true ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    echo "unknown option: $arg" >&2
    usage >&2
    exit 2
    ;;
  *) positional+=("$arg") ;;
  esac
done

root=$(jj root 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null || pwd)
bundle="${positional[0]:-$root/.agents/knowledge}"

if [ ! -d "$bundle" ]; then
  echo "no bundle at $bundle" >&2
  exit 1
fi

results=()
failures=()
failed=0

summary() {
  printf '\n== summary\n'
  if [ "${#results[@]}" -gt 0 ]; then
    printf '%s\n' "${results[@]}"
  fi
  if [ "$failed" -eq 0 ]; then
    printf '\nall OKF gates passed: %s\n' "$bundle"
  else
    printf '\n%d gate(s) failed: %s\n' "$failed" "${failures[*]}" >&2
  fi
}

run() {
  local name=$1
  shift
  printf '\n== %s\n' "$name"
  if "$@"; then
    results+=("PASS  $name")
  else
    local rc=$?
    results+=("FAIL  $name (exit $rc)")
    failures+=("$name")
    failed=$((failed + 1))
    if [ "$fail_fast" = true ]; then
      summary
      exit 1
    fi
  fi
}

run "kdn-okf doctor --parse-only" kdn-okf --bundle "$bundle" doctor --parse-only
run "okf-memory validate --strict --drift" okf-memory validate "$bundle" --strict --drift
run "ai-xf-validate --level 2" ai-xf-validate "$bundle" --level 2
run "okf-rs validate" okf-rs validate "$bundle"
run "okf-rs lint" okf-rs lint "$bundle"
run "okf-rs links --broken --check" okf-rs links "$bundle" --broken --check
if [ -f "$bundle/okf-base.yaml" ]; then
  run "okflint validate" okflint validate --manifest "$bundle/okf-base.yaml" "$bundle"
else
  results+=("SKIP  okflint validate (no okf-base.yaml)")
fi
run "okph validate --strict" okph validate "$bundle" --strict --ignore prefer-absolute-links

summary
if [ "$failed" -ne 0 ]; then
  exit 1
fi

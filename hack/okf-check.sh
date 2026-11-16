#!/usr/bin/env bash
# Run every OKF gate on a bundle in the working tree.
#
# The Nix checks (`okf-memory-validate`, `ai-xf-validate`, `okf-rs-check`, `okflint-validate`,
# `okph-validate`) run the same gates on a sandbox copy. This script is the authoring loop: it
# reads the files as they are, so a fix is one edit away. `nix run .#okf-check` wraps it with the
# tools on PATH; in the devenv shell, run `hack/okf-check.sh` directly.
set -eEuo pipefail

root=$(jj root 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null || pwd)
bundle="${1:-$root/.agents/knowledge}"
shift || true

if [ ! -d "$bundle" ]; then
  echo "no bundle at $bundle" >&2
  exit 1
fi

echo "== kdn-okf doctor --parse-only"
kdn-okf --bundle "$bundle" doctor --parse-only

echo "== okf-memory validate --strict --drift"
okf-memory validate "$bundle" --strict --drift

echo "== ai-xf-validate --level 2"
ai-xf-validate "$bundle" --level 2

echo "== okf-rs validate"
okf-rs validate "$bundle"

echo "== okf-rs lint"
okf-rs lint "$bundle"

echo "== okf-rs links --broken --check"
okf-rs links "$bundle" --broken --check

if [ -f "$bundle/okf-base.yaml" ]; then
  echo "== okflint validate --manifest"
  okflint validate --manifest "$bundle/okf-base.yaml" "$bundle"
else
  echo "== okflint: skipped, no okf-base.yaml in the bundle"
fi

echo "== okph validate --strict"
okph validate "$bundle" --strict --ignore prefer-absolute-links

echo "all OKF gates passed: $bundle"

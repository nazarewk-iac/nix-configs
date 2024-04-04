#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

print_all_roots() {
  nix-store --gc --print-roots | grep -v -E "^(/nix/var|/run/\w+-system|\{memory|/proc)"
}

print_all_roots

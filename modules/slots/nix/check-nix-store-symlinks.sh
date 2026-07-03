#!/usr/bin/env bash
# Reject any staged files that are symlinks pointing into /nix/store.
# Such symlinks are managed by devenv/NixOS/nix-darwin/home-manager and must
# never be committed — edit the source in modules/slots/ instead.
set -eEuo pipefail

failed=0
while IFS= read -r file; do
  if [[ -L "$file" ]]; then
    target="$(readlink "$file")"
    if [[ "$target" == /nix/store/* ]]; then
      echo "ERROR: $file is a symlink to the Nix store ($target)" >&2
      echo "  Edit the source in modules/slots/ or the relevant NixOS/HM module instead." >&2
      failed=1
    fi
  fi
done < <(git diff --cached --name-only --diff-filter=ACM)

exit "$failed"

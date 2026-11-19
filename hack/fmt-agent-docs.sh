#!/usr/bin/env bash
# Format every agent journal file (worklog and board).
#
# `.cache/` is git-ignored, so a tree-wide `nix fmt` skips it. This script pipes each file through
# the repository's own treefmt wrapper in stdin mode, which is the same config, the same prettier
# and the same options that `nix fmt` and `jj fix` use. There is no second table formatter: a second
# one would pad the cells to a different width and the two would flip the file back and forth.
#
# The path given to `--stdin` only selects the formatter and the exclude rules. A path under
# `.cache/` is git-ignored and prettier honours `.gitignore`, so prettier would drop it and the
# content would come back unchanged. A bare `journal.md` is not ignored, so the formatter runs.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
mapfile -d '' files < <(find .cache/agents -type f -name '*.md' -print0 2>/dev/null)
test "${#files[@]}" -gt 0 || exit 0

# The wrapper is `treefmt` with the generated treefmt.toml baked in. One build, then one short call
# per file; `nix fmt` per file would re-evaluate the flake 88 times.
system=$(nix config show system)
treefmt=$(nix build --no-link --print-out-paths ".#formatter.${system}")/bin/treefmt

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
for file in "${files[@]}"; do
  "$treefmt" --quiet --stdin journal.md <"$file" >"$tmp"
  if ! cmp -s "$tmp" "$file"; then
    cat "$tmp" >"$file"
    printf 'reformatted %s\n' "$file"
  fi
done

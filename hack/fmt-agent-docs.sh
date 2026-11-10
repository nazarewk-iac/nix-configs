#!/usr/bin/env bash
# Format every agent journal file (worklog and board).
#
# `.cache/` is git-ignored, so a tree-wide `nix fmt` skips it. This script formats the files
# explicitly, then aligns the Markdown table columns: prettier normalises tables but leaves every
# cell one space wide, and `align-md-tables.py` pads them so the pipes line up in a terminal.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
mapfile -d '' files < <(find .cache/agents -type f -name '*.md' -print0 2>/dev/null)
test "${#files[@]}" -gt 0 || exit 0
nix fmt -- "${files[@]}"
exec ./hack/align-md-tables.py "${files[@]}"

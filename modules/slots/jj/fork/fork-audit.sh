#!/usr/bin/env bash
# List fork-sensitive content in local commits, at line level.
#
# It mirrors the `fork-direct` revset: a file-path match and a changed-line
# match (both from SENSITIVE_FILE_PATTERNS), plus a description match
# (SENSITIVE_MESSAGE_PATTERNS). The patterns are baked in via runtimeEnv.
#
# Usage: jj-fork-audit [--color=auto|always|never] [-q|--quiet] [REVSET]
#   REVSET defaults to local, mutable, described, non-empty commits.
#   --color  when to colorize; "auto" (default) colorizes only on a TTY.
#   -q       suppress the header that lists the patterns and the revset.
#
# It is read-only. For each matching commit it prints the matched lines (with
# file and line number), the matched file paths, and the matched message
# patterns. Exit 1 when it finds a match, 0 when clean, 2 on a usage error.

set -eEuo pipefail

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

color_mode=auto
quiet=0
revset=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --color) color_mode=always ;;
    --color=*) color_mode="${1#*=}" ;;
    -q | --quiet) quiet=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      [ "$#" -gt 0 ] && revset="$1"
      break
      ;;
    -*)
      echo "jj-fork-audit: unknown option '$1'" >&2
      exit 2
      ;;
    *) revset="$1" ;;
  esac
  shift
done

case "$color_mode" in
  auto | always | never) ;;
  *)
    echo "jj-fork-audit: invalid --color '$color_mode' (auto|always|never)" >&2
    exit 2
    ;;
esac

jj root &>/dev/null || {
  echo "jj-fork-audit: not in a jj repo" >&2
  exit 2
}

default_revset='mutable() & ~empty() & ~description("")'
revset="${revset:-$default_revset}"

# shellcheck disable=SC2206
file_patterns=($SENSITIVE_FILE_PATTERNS)
# shellcheck disable=SC2206
msg_patterns=($SENSITIVE_MESSAGE_PATTERNS)

if [ "${#file_patterns[@]}" -eq 0 ] && [ "${#msg_patterns[@]}" -eq 0 ]; then
  echo "jj-fork-audit: no denied patterns configured (this is not a fork repo)" >&2
  exit 0
fi

# Gate color on the mode and, for "auto", on a real TTY (and NO_COLOR unset).
# This keeps the non-TTY paths clean: the Nix sandbox check and any pipe.
use_color=0
if [ "$color_mode" = always ]; then
  use_color=1
elif [ "$color_mode" = auto ] && [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  use_color=1
fi

if [ "$use_color" -eq 1 ]; then
  B=$'\e[1m' D=$'\e[2m' RST=$'\e[0m' CY=$'\e[36m' YE=$'\e[33m'
  grep_color=always
  # matched text bold red; line numbers green; separators grey.
  export GREP_COLORS='ms=01;31:mc=01;31:ln=32:se=90'
else
  B='' D='' RST='' CY='' YE=''
  grep_color=never
fi

# Fixed-string grep args for the file patterns (paths, content, diff).
file_grep=()
for p in "${file_patterns[@]}"; do file_grep+=(-e "$p"); done

if [ "$quiet" -eq 0 ]; then
  printf '%sjj-fork-audit%s — revset: %s%s%s\n' "$B" "$RST" "$D" "$revset" "$RST"
  printf '  denied file patterns:    %s%s%s\n' "$YE" "${file_patterns[*]:-(none)}" "$RST"
  printf '  denied message patterns: %s%s%s\n' "$YE" "${msg_patterns[*]:-(none)}" "$RST"
  echo
fi

# Prefer the jj `fork-direct` alias to select commits; fall back to the whole
# revset when the alias is not loaded (then grep decides per commit).
select_revset="$revset"
if jj log -r 'fork-direct' --no-graph -T '""' &>/dev/null; then
  select_revset="($revset) & fork-direct"
fi

mapfile -t commits < <(jj log -r "$select_revset" --no-graph -T 'change_id.short() ++ "\n"' 2>/dev/null || true)

found=0

for c in "${commits[@]}"; do
  [ -n "$c" ] || continue

  subject="$(jj log -r "$c" --no-graph -T 'description.first_line()' 2>/dev/null || true)"
  desc="$(jj log -r "$c" --no-graph -T 'description' 2>/dev/null || true)"

  # message pattern matches
  msg_hits=""
  for p in "${msg_patterns[@]:-}"; do
    [ -n "$p" ] || continue
    printf '%s' "$desc" | grep -qiF -- "$p" && msg_hits+=" ${YE}'${p}'${RST}"
  done

  # per-file path and line matches
  paths=""
  lines=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    for p in "${file_patterns[@]}"; do
      printf '%s' "$f" | grep -qiF -- "$p" && paths+="    ${f}  ${D}(matches '${p}')${RST}"$'\n'
    done
    if [ "${#file_grep[@]}" -gt 0 ]; then
      # content at this revision — real line numbers; skip binary files
      m="$(jj file show -r "$c" "$f" 2>/dev/null | grep -nIiF --color="$grep_color" "${file_grep[@]}" || true)"
      if [ -n "$m" ]; then
        lines+="    ${CY}${f}${RST}:"$'\n'
        while IFS= read -r ml; do lines+="      ${ml}"$'\n'; done <<< "$m"
      fi
    fi
  done < <(jj diff -r "$c" --name-only 2>/dev/null || true)

  # A commit can match `fork-direct` only through a removed or changed line
  # (for example a scrub that deletes a denied term). The content grep above
  # misses those, so fall back to the diff.
  if [ -z "$paths" ] && [ -z "$lines" ] && [ -z "$msg_hits" ] && [ "${#file_grep[@]}" -gt 0 ]; then
    dm="$(jj diff -r "$c" --git 2>/dev/null | grep -nIiF --color="$grep_color" "${file_grep[@]}" || true)"
    if [ -n "$dm" ]; then
      lines+="    ${D}(matched in the diff only — removed or changed lines):${RST}"$'\n'
      while IFS= read -r dl; do lines+="      ${dl}"$'\n'; done <<< "$dm"
    fi
  fi

  if [ -n "$msg_hits" ] || [ -n "$paths" ] || [ -n "$lines" ]; then
    found=1
    printf '%s● %s%s  %s\n' "$CY" "$c" "$RST" "$subject"
    [ -n "$msg_hits" ] && printf '  %smessage matches:%s%s\n' "$B" "$RST" "$msg_hits"
    [ -n "$paths" ] && {
      printf '  %sfile paths:%s\n' "$B" "$RST"
      printf '%s' "$paths"
    }
    [ -n "$lines" ] && {
      printf '  %slines:%s\n' "$B" "$RST"
      printf '%s' "$lines"
    }
  fi
done

if [ "$found" -eq 0 ]; then
  echo "jj-fork-audit: no fork-sensitive content found in '${revset}'"
fi
exit "$found"

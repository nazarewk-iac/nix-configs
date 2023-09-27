#!/usr/bin/env bash
set -eEuo pipefail
test -z "${DEBUG:-}" || set -x

git_creds_json() {
  git credential fill <<<"url=${1}" | jq -cMsR 'split("\n") | map(select(contains("=")) | split("=") | {key: .[0], value: (.[1:] | join("="))}) | from_entries'
}

uriencode() {
  jq -Rr '@uri' <<<"$1"
}

gitlab-api() {
  local url="$1"
  shift 1
  command curl --fail --silent "$url" "$@" --config - <<<"--header \"Authorization: Bearer ${gitlab_token}\""
}

gitlab-paginate() {
  local url="$1" per_page="${per_page:-100}" page="${page:-1}"
  shift 1

  gitlab-api "$url" --url-query "per_page=${per_page}" --url-query "page=${page}" "$@" | jq -Mc 'if length == 0 then error else . end' 2>/dev/null || return 0
  per_page="${per_page}" page="$((page + 1))" gitlab-paginate "$url" "$@"
}

group-projects-list() {
  local url="$1"
  shift 1
  for group in "$@"; do
    gitlab_token="$(git_creds_json "${url}/$group" | jq -r .password)"
    gitlab-paginate "$url/api/v4/groups/$(uriencode "$group")/projects" --url-query "include_subgroups=${include_subgroups:-"true"}"
  done
}

main() {
  local url="$1"
  shift 1

  echo "Searching for repos in ${url}, groups: ${*}" >&2

  # see https://archives.docs.gitlab.com/15.11/ee/api/projects.html
  # see https://archives.docs.gitlab.com/15.11/ee/api/groups.html#list-a-groups-projects
  group-projects-list "$url" "$@" | jq -sr 'map(.[].http_url_to_repo) | unique[]'
}

main "$@"

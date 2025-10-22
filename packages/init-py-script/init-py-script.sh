#!/usr/bin/env bash
set -eEuo pipefail
trap 'echo "Error when executing $BASH_COMMAND at line $LINENO!" >&2' ERR
# shellcheck disable=SC2059
_log() { printf "$(date -Isec) ${1} ${BASH_SOURCE[1]}:${BASH_LINENO[1]}: ${2}\n" "${@:3}" >&2; }
info() { _log INFO "$@"; }
warn() { _log WARN "$@"; }
info STARTING
trap 'info FINISHED' EXIT
test -z "${DEBUG:-}" || set -x

log_run_direct() {
  info "running: ${out}/python -m '${python_package}.cli' $*"
  PAGER="cat" "${out}/python" -m "${python_package}.cli" "$@"
}

log_run_nix() {
  info "running: nix run '${repo}#${name}' -- $*"
  PAGER="cat" nix run "${repo}#${name}" -- "$@"
}

create_package() {
  cp -r "${template_dir}" "${out}"
  chmod -R ug+w "${out}"
  mv "${out}/${python_package_placeholder}" "${out}/${python_package}"
  find "${out}" -type f -print | tee /dev/stderr | xargs sed -i \
    -e "s/${name_placeholder}/${name}/g" \
    -e "s/${python_package_placeholder}/${python_package}/g"
  git -C "${repo}" add "${out}/*"
}

register_package() {
  local file="${packages}/default.nix"
  test -e "${file}" || return 0

  local insert="${name} = pkgs.callPackage ./${name} {};"
  local pattern="# AUTO_PACKAGE_PLACEHOLDER #"

  grep "= pkgs.callPackage" "${file}" || return 0
  sed -i "/${pattern}/a${insert}" "${file}"
}

link() {
  nix run "${repo}#link-python" -- "${name}"
}

test_run() {
  log_run_nix --help
  log_run_direct
  log_run_direct sub
  log_run_direct dynamic_var
}

find_packages() {
  if test -d "${1}/nix/packages"; then
    printf "%s" "${1}/nix/packages"
  else
    printf "%s" "${1}/packages"
  fi
}

main() {
  : "${name:="${1}"}"
  : "${template_dir:="${BASH_SOURCE[0]%/*}/template"}"
  : "${repo:="$(git rev-parse --show-toplevel)"}"
  : "${packages:="$(find_packages "${repo}")"}"
  : "${force:=0}"
  : "${out="${packages}/${name}"}"


  name="${name,,}"
  name="${name//"_"/"-"}"
  name_placeholder="package-placeholder"

  python_package="${name//"-"/"_"}"
  python_package_placeholder="package_placeholder"

  if test -d "${out}"; then
    warn "already exists '${out}', exitting unless 'force=1'"
    if test "${force}" = 1; then
      info "removing directory due to 'force=1'..."
      rm -r "${out}"
    else
      exit 1
    fi
  fi

  create_package
  register_package
  link
  test_run
}

main "$@"

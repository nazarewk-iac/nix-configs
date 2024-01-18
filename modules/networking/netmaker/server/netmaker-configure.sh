#!/usr/bin/env bash
set -eEuo pipefail

info() {
  echo "$@" >&2
}

make_password() {
  tr -dc A-Za-z0-9 </dev/urandom | head -c "$1"
}

save_config() {
  save_value "${ENV}" "$@"
}

save_secret() {
  save_value "${SECRETS}" "$@"
}

save_value() {
  # loosely based on https://github.com/gravitl/netmaker/blob/dd5a943fa473ad21830133fb1b83421a7ab61a16/scripts/nm-quick.sh#L454-L480
  local FILE="$1" NAME="$2" VALUE
  if test "$#" -ge 3; then
    VALUE="$3"
  else
    VALUE="${!NAME:-""}"
  fi
  if test -z "$VALUE"; then
    # load the default for empty values
    VALUE="$(awk -F'=' "/^$NAME/ { print \$2}" "$DATA_DIR/netmaker.default.env")"
    # trim quotes for docker
    VALUE="$(echo "$VALUE" | sed -E "s|^(['\"])(.*)\1$|\2|g")"
    #info "Default for $NAME=$VALUE"
  fi
  # escape | in the value
  VALUE="${VALUE//|/"\|"}"
  # escape single quotes
  VALUE="${VALUE//"'"/\'\"\'\"\'}"
  # single-quote the value
  VALUE="'${VALUE}'"
  if grep -q "^$NAME=" "$FILE"; then
    sed -i "s|$NAME=.*|$NAME=$VALUE|" "$FILE"
  else
    echo "$NAME=$VALUE" >>"$FILE"
  fi
}

ensure_corefile() {
  if [ ! -f "${COREFILE}" ]; then
    info "Creating ${COREFILE}."
    mkdir -p "${COREFILE%/*}"
    cat <<EOF >"${COREFILE}"
. {
    reload 15s
    hosts ${COREFILE%/*}/netmaker.hosts {
        fallthrough
    }
    forward . 8.8.8.8 8.8.4.4
    log
}
EOF
  else
    info "OK: ${COREFILE} exists."
  fi
}

ensure_mq_password() {
  if ! test -e "${MQ_PASSWORD_FILE}"; then
    mkdir -p "${MQ_PASSWORD_FILE%/*}"
    make_password 30 >"${MQ_PASSWORD_FILE}"
  fi
  save_secret "MQ_PASSWORD" "$(cat "${MQ_PASSWORD_FILE}")"
}

ensure_master_key() {
  if grep "^MASTER_KEY=" "${SECRETS}"; then
    return
  fi
  save_secret "MASTER_KEY" "$(make_password 30)"
}

configure() {
  for file in "${SECRETS}" "${ENV}"; do
    mkdir -p "${file%/*}"
    test -f "${file}" || touch "${file}"
  done

  ensure_corefile
  ensure_mq_password
  ensure_master_key
}

configure
if test "$#" -gt 0; then
  exec "$@"
fi

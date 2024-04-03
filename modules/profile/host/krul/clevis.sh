#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

RUN=0

header_dev="/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04MBA03UR5RXVOGO-0:0-part2"
data_dev="/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2L482L2B1Q1J"
luks_name="krul-main-crypted"
clevis_keyfile="/nazarewk-iskaral/secrets/luks/krul/luks-krul-main-keyfile.clevis.bin"
name="${data_dev##*/}"

json="${luks_name}.clevis.json"
out="${luks_name}.jwe"

info() {
  RUN=0 maybe "$@"
}

maybe() {
  if test "$RUN" == 1; then
    "$@"
  else
    printf '%q ' "$@"
    printf '\n'
  fi
}

info sudo dd if=/dev/random bs=32 count=1 of="${clevis_keyfile}"
info sudo chmod 0600 "${clevis_keyfile}"
info sudo cryptsetup luksAddKey "${header_dev}" "${clevis_keyfile}"

if test -e "${clevis_keyfile}"; then
  sudo cat "${clevis_keyfile}" | clevis encrypt sss "$(jq -cM . "${json}")" >"${out}.new"
elif test -e "${out}"; then
  clevis decrypt <"${out}" | clevis encrypt sss "$(jq -cM . "${json}")" >"${out}.new"
fi

info mv "${out}.new" "${out}"

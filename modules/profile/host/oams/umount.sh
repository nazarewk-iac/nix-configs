#!/usr/bin/env bash
set -xeEuo pipefail
target="${1:-"/mnt"}"
umount -R "${target}" || :
zpool export oams-main || :
cryptsetup close oams-main || :
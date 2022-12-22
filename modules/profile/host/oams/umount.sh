#!/usr/bin/env bash
set -xeEuo pipefail
umount -R /mnt || :
zpool export oams-main || :
cryptsetup close oams-main || :
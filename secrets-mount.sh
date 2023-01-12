#!/usr/bin/env bash
set -eEuo pipefail
cd "${BASH_SOURCE[0]%/*}"

if ! zpool status "nazarewk-iskaral"; then
  zpool import nazarewk-iskaral
fi

if ! mountpoint "/nazarewk-iskaral/secrets/luks"; then
  zfs load-key nazarewk-iskaral || :
  zfs mount nazarewk-iskaral/secrets/luks
fi

if ! mountpoint "/nazarewk-iskaral/secrets/gpg"; then
  zfs load-key nazarewk-iskaral || :
  zfs mount nazarewk-iskaral/secrets/gpg
fi

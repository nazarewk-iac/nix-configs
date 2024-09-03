#!/usr/bin/env bash
set -eEuo pipefail
set -x

pushd "${BASH_SOURCE[0]%/*}"
wd="$PWD"
out="${wd}/netbird"
src="/home/kdn/dev/github.com/netbirdio/netbird"
pushd /home/kdn/dev/github.com/netbirdio/netbird
git reset --hard origin
for patch in "${wd}"/*.patch ; do
  #patch -p0 <"${patch}"
  git apply "${patch}"
done
GOARM=6 GOARCH=arm CGO_ENABLED=0 go build -o "${out}" "${src}/client"
popd
scp "${out}" root@yelk.yelk.lan:/root/netbird
ssh root@yelk.yelk.lan. /root/netbird-try.sh
popd



#!/usr/bin/env bash
# inspired by https://github.com/Mic92/dotfiles/blob/master/nixos/modules/k3s/kill-all.sh
set -xeEuo pipefail
shopt -s nullglob

cgroups=(
  /sys/fs/cgroup/systemd/system.slice/containerd.service*
  /sys/fs/cgroup/systemd/kubepods*
  /sys/fs/cgroup/kubepods*
)

unmounts=(
  /run/cilium/cgroupv2
  /run/containerd
  /run/netns
  /var/lib/kubelet
)

clear_dirs=(
  /opt/cni
  /opt/containerd
  /run/containerd
  /var/lib/calico
  /var/lib/cni
  /var/lib/containerd
  /var/lib/kubelet
  /var/lib/rancher
  /var/lib/rook/*
  /var/log/calico
  /var/log/containers
  /var/log/pods
  /var/run/calico
  /var/run/cilium
  /var/run/containerd
)

clear_files=(
  /etc/cni/net.d/*
  /etc/rancher/k3s/k3s.yaml
)

function main {
  if command -v k3s-node-shutdown ; then
    k3s-node-shutdown "$(hostname)"
  fi
  systemctl stop containerd k3s || :

  readarray -t existing_cgroups < <(only_existing "${cgroups[@]}")
  readarray -t existing_clear_dirs < <(only_existing "${clear_dirs[@]}")
  readarray -t existing_clear_files < <(only_existing "${clear_files[@]}")

  # shellcheck disable=SC2038
  test "${#existing_cgroups[@]}" = 0 || find "${existing_cgroups[@]}" -name cgroup.procs -exec cat {} \; | xargs -r kill -9

  # 1. replace `/` with `\/`
  # 2. join by `|`
  awk_unmounts="$(join_by '|' "${unmounts[@]//\//\\/}")"
  mount | awk '/'"${awk_unmounts}"'/ {print $3}' | xargs -r umount

  dataset="$( (grep /var/lib/containerd/io.containerd.snapshotter.v1.zfs /proc/mounts || :) | awk '{print $1}')"
  test "$dataset" = "" || zfs destroy -R "$dataset"
  test "${#existing_clear_dirs[@]}" = 0 || find "${existing_clear_dirs[@]}" -mindepth 1 -maxdepth 1 -exec rm -vrf -- '{}' \;
  test "${#existing_clear_files[@]}" = 0 || rm -v -- "${existing_clear_files[@]}"
}

function join_by {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

function only_existing {
  test "$#" != 0 || return 0
  for entry in "${@}"; do
    test -e "${entry}" || continue
    echo "${entry}"
  done
}

main "$@"

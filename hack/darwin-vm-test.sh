#!/usr/bin/env bash
# Boot an ephemeral macOS guest, activate a nix-darwin configuration in it, and assert the result.
#
#   nix run '.#darwin-vm-test' -- bake                 # one time, 40 to 60 min
#   nix run '.#darwin-vm-test' -- run                  # per checkpoint, 5 to 15 min
#   nix run '.#darwin-vm-test' -- run --cold --keep
#
# Full design: docs/tasks/2026-09/darwin-vm-testing/design.md
#
# Three rules this script must never break.
#
#  1. It needs no host `sudo`. Apple Virtualization runs unprivileged under the
#     `com.apple.security.virtualization` entitlement. The script refuses to run as root, so nobody
#     adds a `sudo` by habit. `sudo` INSIDE the guest is needed and permitted — nix-darwin
#     activation needs root, and the guest is a throwaway.
#
#  2. It deletes only a guest it created in this run, under the `kdn-vmtest-clone-` prefix. It
#     never deletes the base image and never the golden image. `delete_clone` holds the guard, and
#     it is the only `tart delete` in the file.
#
#  3. It never calls `limactl`, so it cannot reach the `nix-rosetta-builder` guest. It sets no Nix
#     option either, so it cannot set `kdn.rosetta-builder.guest.minFree` or `.maxFree`. A non-null
#     value there regenerates `lima.yaml`, and the start script then runs `limactl delete --force`
#     (modules/den/aspects/rosetta-builder.nix:31-37). Never add one.
#
# UNVERIFIED, and each one needs a check before the first real run:
#   * the exact argument shape of `tart exec`     — see guest_sh
#   * the output shape of `tart list`             — see vm_exists
#   * passwordless `sudo` in the base image       — see grant_sudo
#   * `sshd` running in the base image            — needed by copy_closure
#   * whether a Nix-built `ssh` reaches a tart guest on macOS 26 — see copy_closure
set -eEuo pipefail

BASE_IMAGE="${KDN_VMTEST_BASE_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-base:latest}"
BASE_VM="${KDN_VMTEST_BASE_VM:-kdn-vmtest-base}"
GOLDEN_VM="${KDN_VMTEST_GOLDEN_VM:-kdn-vmtest-golden}"
CLONE_PREFIX="kdn-vmtest-clone-"
SUBJECT="${KDN_VMTEST_SUBJECT:-.#denConfigurations.host-darwin.system.build.toplevel}"
GUEST_USER="${KDN_VMTEST_GUEST_USER:-admin}"
GUEST_PASSWORD="${KDN_VMTEST_GUEST_PASSWORD:-admin}"
DISK_SIZE="${KDN_VMTEST_DISK_SIZE:-120}"
BOOT_BUDGET="${KDN_VMTEST_BOOT_BUDGET:-120}"
KEY_DIR=""

# `tart clone` prunes the local image cache on its own, and a prune can evict the base image in the
# middle of a run. definition.md blocker 10 records it.
export TART_NO_AUTO_PRUNE=1

log() { printf '── %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Rule 1. Apple Virtualization needs no root, and a root run leaves root-owned state behind.
if [ "$(id -u)" -eq 0 ]; then
  die "run this as your own user, never with sudo"
fi

tart_bin=""
for candidate in "$(command -v tart || true)" /opt/homebrew/bin/tart /usr/local/bin/tart; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    tart_bin="$candidate"
    break
  fi
done
if [ -z "$tart_bin" ]; then
  die "tart not found. Install it: brew install openai/tools/tart
The nixpkgs package is stale at 2.30.6 and marked unfree, so do not use it."
fi

# UNVERIFIED: the exact argument shape of `tart exec`. Confirm with `tart exec --help`, then correct
# this one function. Every guest command goes through it, so one correction covers the whole file.
guest_sh() {
  local vm="$1"
  local script="$2"
  "$tart_bin" exec "$vm" /bin/bash -lc "$script"
}

# UNVERIFIED: the output shape of `tart list`. Confirm, then correct this one function.
vm_exists() {
  "$tart_bin" list 2>/dev/null | grep -qE "(^|[[:space:]])$1([[:space:]]|\$)"
}

stop_vm() {
  "$tart_bin" stop "$1" >/dev/null 2>&1 || true
}

# Rule 2. This is the only `tart delete` in the file, and the prefix check is the guard.
delete_clone() {
  local vm="$1"
  case "$vm" in
    "$CLONE_PREFIX"?*) : ;;
    *) die "refuse to delete '$vm' — only a guest under the '$CLONE_PREFIX' prefix" ;;
  esac
  if [ "$vm" = "$BASE_VM" ] || [ "$vm" = "$GOLDEN_VM" ]; then
    die "refuse to delete the base image or the golden image"
  fi
  log "delete the clone $vm"
  "$tart_bin" delete "$vm"
}

wait_boot() {
  local vm="$1"
  local waited=0
  log "wait for the guest agent, budget ${BOOT_BUDGET}s"
  while [ "$waited" -lt "$BOOT_BUDGET" ]; do
    if guest_sh "$vm" 'true' >/dev/null 2>&1; then
      log "the guest answers after ${waited}s"
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  die "the guest did not answer in ${BOOT_BUDGET}s"
}

# UNVERIFIED: whether the base image gives the guest user passwordless `sudo`. This grants it once,
# so every later step needs no password on stdin. The guest is a throwaway. Never do this on a real
# machine.
grant_sudo() {
  local vm="$1"
  log "grant passwordless sudo in the guest"
  guest_sh "$vm" "echo '$GUEST_PASSWORD' | sudo -S -p '' sh -c \"echo '$GUEST_USER ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/kdn-vmtest\""
}

# The Lix installer, not Determinate. nix-darwin ABORTS activation when it detects Determinate
# ("error: Determinate detected, aborting activation"), and this repository runs Lix 2.95.2.
install_nix() {
  local vm="$1"
  if guest_sh "$vm" 'test -e /nix/var/nix/profiles/default/bin/nix' >/dev/null 2>&1; then
    log "Nix is already installed in the guest"
    return 0
  fi
  log "install Lix in the guest — minutes"
  guest_sh "$vm" "curl -sSfL https://install.lix.systems/lix | sh -s -- install --no-confirm"
  log "write the guest nix.conf opinions"
  guest_sh "$vm" "printf '%s\n' 'experimental-features = nix-command flakes' 'trusted-users = root $GUEST_USER' | sudo tee -a /etc/nix/nix.conf >/dev/null"
  guest_sh "$vm" 'sudo launchctl kickstart -k system/org.nixos.nix-daemon'
}

# nix-darwin renames these four files on the FIRST activation only. So a golden image that already
# holds the `*.before-nix-darwin` files can never prove the first-time takeover again. That is why
# assertion A3 belongs to the `--cold` path only. See design.md section 6.
prepare_etc() {
  local vm="$1"
  log "move the image's own shell start-up files aside"
  # The two single-quoted blocks below go to the GUEST shell verbatim. `$f` and `$HOME` must stay
  # unexpanded here, because the guest expands them. So SC2016 is a false positive at both sites.
  # shellcheck disable=SC2016
  guest_sh "$vm" 'for f in /etc/bashrc /etc/zshrc /etc/zshenv /etc/zprofile; do
      if [ -e "$f" ] && [ ! -e "$f.before-nix-darwin" ]; then sudo mv "$f" "$f.before-nix-darwin"; fi
    done'
  # shellcheck disable=SC2016
  guest_sh "$vm" 'for f in "$HOME/.zprofile" "$HOME/.profile"; do
      if [ -e "$f" ] || [ -L "$f" ]; then mv "$f" "$f.before-nix-darwin"; fi
    done'
}

# `nix copy` needs key authentication. Generate a throwaway key per run and plant it. The key stays
# in a temporary directory, and the guest is destroyed after the run.
plant_key() {
  local vm="$1"
  local pub
  KEY_DIR="$(mktemp -d)"
  /usr/bin/ssh-keygen -q -t ed25519 -N '' -f "$KEY_DIR/id" -C kdn-vmtest
  pub="$(cat "$KEY_DIR/id.pub")"
  log "plant the throwaway key in the guest"
  guest_sh "$vm" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && printf '%s\n' '$pub' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
}

# `nix copy` picks `ssh` from PATH. A Nix-built `ssh` cannot reach a LUME guest on macOS 26, and
# whether the same fault hits a TART guest is UNVERIFIED. So put /usr/bin first for this one call.
# Fallback, if it still fails: `nix-store --export` piped through `tart exec`. That path is also
# UNVERIFIED, so measure it before you adopt it.
copy_closure() {
  local vm="$1"
  local toplevel="$2"
  local ip
  ip="$("$tart_bin" ip "$vm")"
  log "copy the closure to $GUEST_USER@$ip"
  PATH="/usr/bin:$PATH" \
    NIX_SSHOPTS="-i $KEY_DIR/id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes" \
    nix copy --to "ssh-ng://$GUEST_USER@$ip" "$toplevel"
}

# Assertion A1: the activation script RUNS and exits 0. Every current Darwin check only greps its
# text, so this is the whole point of the harness.
activate_subject() {
  local vm="$1"
  local toplevel="$2"
  log "set the system profile"
  guest_sh "$vm" "sudo /nix/var/nix/profiles/default/bin/nix-env -p /nix/var/nix/profiles/system --set '$toplevel'"
  log "A1 activate"
  guest_sh "$vm" "sudo '$toplevel/activate'"
}

assert_all() {
  local vm="$1"
  local toplevel="$2"
  local cold="$3"
  local got

  log "A2 /run/current-system resolves to the subject"
  got="$(guest_sh "$vm" 'readlink -f /run/current-system' | tr -d '\r')"
  if [ "$got" != "$toplevel" ]; then
    die "A2 failed: /run/current-system is '$got', expected '$toplevel'"
  fi

  if [ "$cold" -eq 1 ]; then
    log "A3 the first-time /etc takeover left the backup file"
    guest_sh "$vm" 'test -e /etc/zshrc.before-nix-darwin' ||
      die "A3 failed: /etc/zshrc.before-nix-darwin is absent"
  else
    log "A3 skipped — the golden image already holds the backup files. Use --cold for A3."
  fi

  log "A4 /etc/zshrc names nix-darwin"
  guest_sh "$vm" 'grep -q nix-darwin /etc/zshrc' ||
    die "A4 failed: /etc/zshrc does not name nix-darwin"

  log "A5 a second activation converges"
  guest_sh "$vm" "sudo '$toplevel/activate'" ||
    die "A5 failed: the second activation exited non-zero"

  # NOT asserted: `org.nixos.rosetta-builderd`. The subject includes `kdn.rosetta-builder`, and a
  # macOS guest cannot run a nested virtual machine (`kern.hv_support: 0`, definition.md blocker
  # 13). So that daemon can never start here. Version 2 asserts every other launchd unit.
  log "every assertion passes"
}

cleanup() {
  if [ -n "$KEY_DIR" ] && [ -d "$KEY_DIR" ]; then
    rm -rf "$KEY_DIR"
  fi
}
trap cleanup EXIT

cmd_bake() {
  if vm_exists "$BASE_VM"; then
    log "the base guest $BASE_VM is present, skip the pull"
  else
    log "pull $BASE_IMAGE — 27.31 GB compressed, a 50 GB guest disk"
    "$tart_bin" clone "$BASE_IMAGE" "$BASE_VM"
  fi

  if vm_exists "$GOLDEN_VM"; then
    die "the golden guest $GOLDEN_VM exists. Delete it by hand when you want a new one."
  fi

  log "clone the base into the golden guest — APFS copy-on-write"
  "$tart_bin" clone "$BASE_VM" "$GOLDEN_VM"
  "$tart_bin" set "$GOLDEN_VM" --disk-size "$DISK_SIZE"

  log "start the golden guest"
  "$tart_bin" run --no-graphics "$GOLDEN_VM" &
  wait_boot "$GOLDEN_VM"

  # Poll `df`, never `diskutil`. `diskutil` queues on `diskmanagementd`, and it deadlocks against
  # the guest agent. definition.md records the trap.
  log "guest disk: $(guest_sh "$GOLDEN_VM" 'df -h /' | tail -n 1)"

  grant_sudo "$GOLDEN_VM"
  install_nix "$GOLDEN_VM"
  prepare_etc "$GOLDEN_VM"

  log "stop the golden guest"
  stop_vm "$GOLDEN_VM"
  log "bake done. Next: nix run '.#darwin-vm-test' -- run"
}

cmd_run() {
  local cold=0
  local keep=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cold) cold=1 ;;
      --keep) keep=1 ;;
      --subject)
        shift
        SUBJECT="${1:?--subject needs a flake attribute}"
        ;;
      *) die "unknown flag: $1" ;;
    esac
    shift
  done

  local source_vm
  if [ "$cold" -eq 1 ]; then
    source_vm="$BASE_VM"
  else
    source_vm="$GOLDEN_VM"
  fi
  vm_exists "$source_vm" ||
    die "the guest '$source_vm' is absent. Run: nix run '.#darwin-vm-test' -- bake"

  log "build the subject on the host: $SUBJECT"
  local toplevel
  toplevel="$(nix build --no-link --print-out-paths "$SUBJECT")"
  log "subject toplevel: $toplevel"

  local clone
  clone="$CLONE_PREFIX$(date -u +%Y%m%dT%H%M%SZ)"
  log "clone $source_vm into $clone"
  "$tart_bin" clone "$source_vm" "$clone"
  "$tart_bin" set "$clone" --disk-size "$DISK_SIZE"
  "$tart_bin" run --no-graphics "$clone" &

  # shellcheck disable=SC2064
  trap "stop_vm '$clone'; cleanup" EXIT

  wait_boot "$clone"
  grant_sudo "$clone"
  if [ "$cold" -eq 1 ]; then
    # A cold run leaves /etc untouched, so A3 can read the backup files after the activation.
    install_nix "$clone"
  fi
  plant_key "$clone"
  copy_closure "$clone" "$toplevel"
  activate_subject "$clone" "$toplevel"
  assert_all "$clone" "$toplevel" "$cold"

  log "stop the clone"
  stop_vm "$clone"
  trap cleanup EXIT

  if [ "$keep" -eq 1 ]; then
    log "keep $clone for inspection. Delete it by hand: tart delete $clone"
  else
    delete_clone "$clone"
  fi
  log "PASS"
}

case "${1:-}" in
  bake)
    shift
    cmd_bake "$@"
    ;;
  run)
    shift
    cmd_run "$@"
    ;;
  *)
    die "usage: darwin-vm-test (bake | run [--cold] [--keep] [--subject <flake attr>])"
    ;;
esac

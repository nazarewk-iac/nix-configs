# The container runner on brys, and the one container that proves it works.
#
# Host-LOCAL module (like `./sensors.nix`): the runner itself is the den aspect
# `modules/den/aspects/containers.nix`, which imports the universal module and turns
# `kdn.containers.enable` on. That aspect has no entry in the den registry
# (`modules/den/lib.nix`), so `denLib.imports { aspects = [ … ]; }` cannot name it and this host
# imports it by path — the same wiring `hosts/etra/containers.nix` uses.
#
# ## Why a container runner on the LLM workstation
#
# The runner is one containerd daemon plus a unit per container: no k3s, no kubelet, no control
# plane. On brys the point is the path, not a workload — containerd configuration, the nix
# snapshotter, image load and `nerdctl run` have to work on this host before anything real is put
# behind them.
#
# ## The proof container
#
# `brys-hello` is CPU-only on purpose: no `devices`, so it never touches the R9700 and cannot
# disturb the resting `max` profile. It prints one line every 30 s, and it appends one line to
# `${KDN_STATE_DIR}/starts.log` on every start — the host reads that file back after a restart,
# which is what makes the state mount, not the log, the proof.
#
# The image is a nix-snapshotter image, so its layers are Nix store paths and nothing is pulled or
# duplicated. `--net=none` keeps it off the default bridge, which would need CNI configuration this
# host does not have.
#
# ## The state root is a dataset
#
# `stateDir` stays at its default (`/var/lib/kdn/brys-hello`): the dataset mountpoint must follow
# the contract, not a second declaration. The module's oneshot creates
# `brys-main/brys/kdn/services/brys-hello` with `mountpoint`, `refquota`, `compression=zstd`,
# `atime=off` and `xattr=sa`, so a backup is `zfs snapshot` + `zfs send` and a restore is
# `zfs receive` + `nixos-rebuild switch`.
#
# This matters more on brys than on a host with a persistent root: brys runs a tmpfs root, so
# `/var/lib/kdn` is empty at every boot. The dataset is where the state actually lives.
#
# ## The nix-snapshotter patch: one upstream incompatibility
#
# The nix snapshotter emits one bind mount per store path of the image closure, in the order of
# `closure-info/store-paths`, which is sorted by store-path hash. Two callers depend on that order,
# and the closure order breaks both:
#
# 1. containerd 2.4.1 builds the container spec with `fsview.FSMounts`, which opens the source of
#    the LAST mount with `os.OpenRoot`. That call accepts a directory only, and containerd returns
#    its `ENOTDIR` unchanged, so `nerdctl create` fails with
#    `open <store path>: not a directory`. An image config json is a plain FILE in the closure, so
#    an image whose config hash sorts last cannot be created.
# 2. `nerdctl` mounts the entries into one temporary directory in order, and every bind mount lands
#    on a path that the snapshot root (`mounts[0]`) provides. A bind mount placed before the root
#    fails with `ENOENT`.
#
# Measured 2026-11-21 on brys: `sdl7va0q…-config-brys-hello.json` was the last of 15 store paths,
# and the unit stayed in `activating`. `hosts/etra/` misses the bug by luck — its closures end with
# a directory.
#
# `./nix-snapshotter-file-mounts-first.patch` keeps the snapshot root first and ranks the rest:
# file store paths first, directory store paths last. The bind mounts are otherwise
# order-independent, so that is the whole fix. The patch is host-local on purpose: the real fix
# belongs upstream (containerd should treat a non-directory mount source as "not implemented" and
# fall back to mounting), and it is one hunk to carry until then.
{ lib, pkgs, ... }:
let
  # The runner binary with the mount-order patch. The image below still comes from the unpatched
  # `pkgs.nix-snapshotter.buildImage`: the patch changes the runtime only.
  nixSnapshotter = pkgs.nix-snapshotter.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./nix-snapshotter-file-mounts-first.patch ];
  });

  helloImage = pkgs.nix-snapshotter.buildImage {
    name = "brys-hello";
    tag = "latest";
    # The image reference is `nix:0<tar-in-the-store>`: containerd reads the layers straight from
    # the Nix store, with no registry in between.
    resolvedByNix = true;
    config.Cmd = [ "${pkgs.hello}/bin/hello" ];
    # One directory, extracted at `/`, so the container rootfs holds
    # `/bin/brys-hello-entrypoint`. The script's own references (bash, coreutils) are what put the
    # rest of the closure in the image layer.
    copyToRoot = pkgs.buildEnv {
      name = "brys-hello-root";
      pathsToLink = [ "/bin" ];
      paths = [
        (pkgs.writeShellScriptBin "brys-hello-entrypoint" ''
          set -eu
          ${pkgs.hello}/bin/hello
          # One line per start, inside the state root the contract hands over.
          ${pkgs.coreutils}/bin/date -Iseconds >> "''${KDN_STATE_DIR:?KDN_STATE_DIR is unset}/starts.log"
          # A one-shot command under the module's `Restart = "always"` would restart in a loop and
          # never show up in `nerdctl ps`, so the entrypoint stays in the foreground.
          while :; do
            ${pkgs.coreutils}/bin/date -Iseconds
            ${pkgs.coreutils}/bin/sleep 30
          done
        '')
      ];
    };
  };
in
{
  imports = [ ../../modules/den/aspects/containers.nix ];

  kdn.containers.containers.brys-hello = {
    image = helloImage;
    cmd = [ "/bin/brys-hello-entrypoint" ];
    extraArgs = [ "--net=none" ];
    stateDataset = {
      name = "brys-main/brys/kdn/services/brys-hello";
      refquota = "1G";
    };
  };

  # The universal module names the stock binary; this host names the patched one (see above).
  systemd.services.nix-snapshotter.serviceConfig.ExecStart = lib.mkForce (
    "${lib.getExe' nixSnapshotter "nix-snapshotter"}"
  );
}

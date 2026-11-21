# The container runner on etra, and the containers that prove it works.
#
# Host-LOCAL module (like ./litellm.nix): the runner itself is the den aspect
# `modules/den/aspects/containers.nix`, which imports the universal module and turns
# `kdn.containers.enable` on. That file is a plain module today — it has no entry in the
# den registry (`modules/den/lib.nix`), so `denLib.imports { aspects = [ … ]; }` cannot name
# it and this host imports it by path.
#
# ## Why a container on the router at all
#
# etra has no GPU and no cluster. A container here is a process, not a workload: containerd
# runs it and the image layers are Nix store paths, so nothing is pulled or duplicated. The
# first container is deliberately trivial — it exists to prove the whole path on a real host
# (containerd config, the nix snapshotter, image load, `nerdctl run`, journal output).
#
# ## The proof containers
#
# `workshop-hello` runs `pkgs.hello` and then sleeps. A one-shot command under the module's
# `Restart = "always"` would restart in a loop and never be visible in `nerdctl ps`, so the
# image carries a tiny entrypoint that prints and then blocks. The image's own `Cmd` stays
# the trivial `hello`, exactly as the proof needs it.
#
# Both containers also prove the state contract, and they cover its two halves:
#
# - `workshop-hello` keeps its state in a PLAIN DIRECTORY. This is the contract on a host with
#   no dataset: the module creates `/var/lib/kdn/workshop-hello`, mounts it at the same path
#   and exports it as `KDN_STATE_DIR`. Nothing in the definition mentions a filesystem.
# - `workshop-state` keeps its state in a DEDICATED DATASET (`etra-main/etra/kdn/services/…`),
#   created by the module's oneshot with `mountpoint`, `refquota`, `compression=zstd`,
#   `atime=off` and `xattr=sa`. A backup is `zfs snapshot` + `zfs send`; a restore is
#   `zfs receive` + `nixos-rebuild switch`.
#
# etra has a pool (`etra-main`) even though the task notes called it GPU-less and pool-less, so
# both halves are provable on this host. The plain-directory container stays as the regression
# test for the non-ZFS case.
{ pkgs, ... }:
let
  # One image, two containers: the same derivation means the same store path, so the second
  # `copy-to-containerd` is a no-op.
  helloImage = pkgs.nix-snapshotter.buildImage {
    name = "workshop-hello";
    tag = "latest";
    # The image reference is `nix:0<tar-in-the-store>` instead of `name:tag`: containerd
    # reads the layers straight from the Nix store, with no registry in between.
    resolvedByNix = true;
    config.Cmd = [ "${pkgs.hello}/bin/hello" ];
    # One directory, extracted at `/`, so the container rootfs holds
    # `/bin/workshop-hello-entrypoint`. The script's own references (bash, hello, coreutils)
    # are what put the rest of the closure in the image layer.
    copyToRoot = pkgs.buildEnv {
      name = "workshop-hello-root";
      pathsToLink = [ "/bin" ];
      paths = [
        (pkgs.writeShellScriptBin "workshop-hello-entrypoint" ''
          set -eu
          ${pkgs.hello}/bin/hello
          # One line per start, inside the state root the contract hands over. The host reads
          # the same file back, which is what makes the mount, not the log, the proof.
          ${pkgs.coreutils}/bin/date -Iseconds >> "''${KDN_STATE_DIR:?KDN_STATE_DIR is unset}/starts.log"
          exec ${pkgs.coreutils}/bin/sleep infinity
        '')
      ];
    };
  };
in
{
  imports = [ ../../modules/den/aspects/containers.nix ];

  kdn.containers.containers.workshop-hello = {
    image = helloImage;
    cmd = [ "/bin/workshop-hello-entrypoint" ];
    # No network at all: no port to publish, and the default nerdctl bridge would need CNI
    # configuration this host does not have.
    extraArgs = [ "--net=none" ];
  };

  kdn.containers.containers.workshop-state = {
    image = helloImage;
    cmd = [ "/bin/workshop-hello-entrypoint" ];
    extraArgs = [ "--net=none" ];
    # `stateDir` is left at its default (`/var/lib/kdn/workshop-state`) on purpose: the dataset
    # mountpoint must follow the contract, not a second declaration.
    stateDataset = {
      name = "etra-main/etra/kdn/services/workshop-state";
      refquota = "1G";
    };
  };
}

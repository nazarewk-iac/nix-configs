# The container runner on etra, and the first container that proves it works.
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
# ## The proof container
#
# `workshop-hello` runs `pkgs.hello` and then sleeps. A one-shot command under the module's
# `Restart = "always"` would restart in a loop and never be visible in `nerdctl ps`, so the
# image carries a tiny entrypoint that prints and then blocks. The image's own `Cmd` stays
# the trivial `hello`, exactly as the proof needs it.
{ pkgs, ... }:
{
  imports = [ ../../modules/den/aspects/containers.nix ];

  kdn.containers.containers.workshop-hello = {
    image = pkgs.nix-snapshotter.buildImage {
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
            exec ${pkgs.coreutils}/bin/sleep infinity
          '')
        ];
      };
    };
    cmd = [ "/bin/workshop-hello-entrypoint" ];
    # No network at all: no port to publish, and the default nerdctl bridge would need CNI
    # configuration this host does not have.
    extraArgs = [ "--net=none" ];
  };
}

# nix-snapshotter: containers whose layers are Nix store paths.
#
# This is the workshop's target container path. An image is a manifest over store paths that are
# already on disk, so nothing is pulled, nothing is pushed, and nothing is duplicated — the reason
# `dockerTools.buildImage` is not used.
#
# It is containerd-only (the upstream author confirms it does not work with docker-ce or podman).
# The same containerd can later be k3s's runtime, so a container written here becomes a Pod with a
# changed reference and no changed image.
#
# `nerdctl` is the CLI. The image reference is `nix:0${image}`.
#
# STATUS: the containerd side evaluates and the plugin binary is 0.4.0, but **the image builder in
# nixpkgs does not work**: `pkgs.nix-snapshotter.buildImage` is a `callPackage` that needs arguments
# from the upstream flake's own scope and aborts with `Function called without required argument
# "globset"`. Building an image therefore needs the pdtpartners flake as a flake input (or a
# hand-written manifest), which is the next step. Nothing here is deployed yet.
{ pkgs, lib, ... }:
let
  socket = "/run/nix-snapshotter/nix-snapshotter.sock";

  # The snapshotter reads one TOML file; these are the defaults from its own config package, written
  # out so the unit has no hidden state.
  config = pkgs.writeText "nix-snapshotter.toml" ''
    address = "${socket}"
    root = "/var/lib/containerd/io.containerd.snapshotter.v1.nix"

    [image_service]
    enable = true
    containerd_address = "/run/containerd/containerd.sock"
  '';
in
{
  virtualisation.containerd = {
    enable = true;
    settings = {
      # containerd has to know the plugin before it will route a snapshot request to it.
      proxy_plugins.nix = {
        type = "snapshot";
        address = socket;
      };
    };
  };

  systemd.services.nix-snapshotter = {
    description = "nix-snapshotter - containerd snapshotter that understands Nix store paths";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    # A snapshotter without containerd is useless, and a stale one after a containerd restart is
    # worse than none: both follow containerd's lifecycle.
    partOf = [ "containerd.service" ];
    restartTriggers = [ config ];
    path = [ pkgs.nix ];
    serviceConfig = {
      Type = "notify";
      ExecStart = "${lib.getExe' pkgs.nix-snapshotter "nix-snapshotter"} --config ${config}";
      Restart = "always";
      RestartSec = "2";
      Delegate = "yes";
      KillMode = "mixed";
      StateDirectory = "containerd";
      RuntimeDirectory = "nix-snapshotter";
      RuntimeDirectoryPreserve = "yes";
    };
  };

  environment.systemPackages = [ pkgs.nerdctl ];
  environment.extraInit = ''
    if [ -z "$CONTAINERD_ADDRESS" ]; then
      export CONTAINERD_ADDRESS=/run/containerd/containerd.sock
    fi
    if [ -z "$CONTAINERD_SNAPSHOTTER" ]; then
      export CONTAINERD_SNAPSHOTTER=nix
    fi
  '';
}

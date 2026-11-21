# Declarative containers on containerd + nix-snapshotter, without a cluster.
#
# `nerdctl` talks to containerd directly, so a container is a systemd unit and nothing else — no
# k3s, no kubelet, no control plane on a host whose job is routing. The image is a nix-snapshotter
# image: its layers are Nix store paths, so nothing is pulled, pushed or duplicated.
#
# The container definition is data, deliberately shaped like a Pod spec (image, cmd, args, env,
# volumes, devices, ports, health). When a cluster does appear, the same block renders into a Pod and
# the runner changes; the definition does not.
#
#   kdn.containers.enable = true;
#   kdn.containers.containers.whisper = {
#     image = pkgs.nix-snapshotter.buildImage { name = "whisper"; … };
#     cmd = [ "whisper-server" "--port" "8089" ];
#     ports = [ "127.0.0.1:8089:8089" ];
#   };
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kdn.containers;

  containerType = lib.types.submodule {
    options = {
      image = lib.mkOption {
        type = lib.types.package;
        description = "A nix-snapshotter image (`pkgs.nix-snapshotter.buildImage`).";
      };
      cmd = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Overrides the image's command.";
      };
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Arguments appended to the command.";
      };
      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Environment; renders as `-e`, a ConfigMap later.";
      };
      volumes = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "host path -> container path; renders as `-v`, a PVC later.";
      };
      devices = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Device nodes to expose, e.g. `/dev/dri` or `/dev/kfd`. Engine containers only.";
      };
      ports = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Port mappings, `host:container` or `addr:host:container`.";
      };
      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Anything else for `nerdctl run`.";
      };
    };
  };

  # containerd spells a platform the Go way (`os/arch`), so the CPU name needs the Go spelling.
  # The transfer service matches on the OS alone unless `check_platform_supported` is set, so an
  # unmapped CPU only loses precision, not the match.
  goArchNames = {
    x86_64 = "amd64";
    aarch64 = "arm64";
  };
  goArch =
    goArchNames.${pkgs.stdenv.hostPlatform.parsed.cpu.name} or pkgs.stdenv.hostPlatform.parsed.cpu.name;
  goPlatform = "linux/${goArch}";

  # A nix-snapshotter image is a tar in the Nix store, referenced as `nix:0<tar>`: no registry
  # serves that name, so containerd has to be told about the image before `nerdctl run` resolves
  # it. `copyToContainerd` is the image's own `nix2container load` script, and the load also
  # unpacks the image with the `nix` snapshotter.
  loadImage = c: "${c.image.copyToContainerd { }}/bin/copy-to-containerd";

  runArgs =
    name: c:
    lib.concatStringsSep " " (
      [
        "${pkgs.nerdctl}/bin/nerdctl"
        "run"
        "--name"
        name
        "--snapshotter"
        "nix"
      ]
      ++ map (p: "-p ${p}") c.ports
      ++ map (d: "--device ${d}") c.devices
      ++ lib.mapAttrsToList (k: v: "-e ${k}=${v}") c.env
      ++ lib.mapAttrsToList (h: v: "-v ${h}:${v}") c.volumes
      ++ c.extraArgs
      ++ [ "nix:0${c.image}" ]
      ++ c.cmd
      ++ c.args
    );

  containerUnit = name: c: {
    description = "container ${name}";
    wantedBy = [ "multi-user.target" ];
    after = [
      "containerd.service"
      "nix-snapshotter.service"
    ];
    requires = [
      "containerd.service"
      "nix-snapshotter.service"
    ];
    path = [ pkgs.nerdctl ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5";
      # Reloading an image containerd already holds is a no-op, so this stays safe across
      # restarts and across a containerd restart.
      ExecStartPre = loadImage c;
      ExecStart = runArgs name c;
      ExecStop = "${pkgs.nerdctl}/bin/nerdctl stop ${name}";
      ExecStopPost = "${pkgs.nerdctl}/bin/nerdctl rm -f ${name}";
    };
  };
in
{
  options.kdn.containers = {
    enable = lib.mkEnableOption "containerd with nix-snapshotter and declarative containers";
    containers = lib.mkOption {
      type = lib.types.attrsOf containerType;
      default = { };
      description = "Containers to run, one systemd unit each.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.containerd = {
      enable = true;
      settings = {
        proxy_plugins.nix = {
          type = "snapshot";
          address = "/run/nix-snapshotter/nix-snapshotter.sock";
        };

        # The transfer service unpacks an imported image only for a `(platform, snapshotter)`
        # pair listed here, and its built-in default lists `overlayfs` alone. Without a `nix`
        # entry, `nix2container load` and `ctr images import --snapshotter nix` fail with
        # "unable to initialize unpacker: no unpack platforms defined" (containerd issue
        # #11606), and an image unpacked through the fallback path loses the store-path
        # annotations, so its container starts with an empty `/nix/store`.
        #
        # Declaring this list REPLACES the default, so `overlayfs` has to stay in it.
        plugins."io.containerd.transfer.v1.local".unpack_config = [
          {
            platform = goPlatform;
            snapshotter = "overlayfs";
          }
          {
            platform = goPlatform;
            snapshotter = "nix";
          }
        ];
      };
    };

    systemd.services = {
      nix-snapshotter = {
        description = "nix-snapshotter - containerd snapshotter over Nix store paths";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        partOf = [ "containerd.service" ];
        path = [ pkgs.nix ];
        serviceConfig = {
          Type = "notify";
          ExecStart = "${lib.getExe' pkgs.nix-snapshotter "nix-snapshotter"}";
          Restart = "always";
          RestartSec = "2";
          Delegate = "yes";
          KillMode = "mixed";
          StateDirectory = "containerd";
          RuntimeDirectory = "nix-snapshotter";
          RuntimeDirectoryPreserve = "yes";
        };
      };
    }
    // lib.mapAttrs' (
      name: c: lib.nameValuePair "container-${name}" (containerUnit name c)
    ) cfg.containers;

    environment.systemPackages = [ pkgs.nerdctl ];
    environment.extraInit = ''
      : "''${CONTAINERD_ADDRESS:=/run/containerd/containerd.sock}"
      : "''${CONTAINERD_SNAPSHOTTER:=nix}"
      export CONTAINERD_ADDRESS CONTAINERD_SNAPSHOTTER
    '';
  };
}

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
#
# ## State is a path, and the filesystem behind it is the host's business
#
# Every container gets a state root: `stateDir`, `/var/lib/kdn/<name>` by default, mounted at the
# same absolute path inside the container and handed to it as `KDN_STATE_DIR`. Nothing the service
# must keep lives anywhere else, so a backup is one directory and a restore is that directory plus
# the image revision from the repo.
#
# On a host with ZFS the directory is a dedicated dataset (`stateDataset`), which makes the backup
# `zfs snapshot` + `zfs send` and the restore `zfs receive` + `nixos-rebuild switch`. On a host
# without ZFS the same path stays a plain directory: the contract is the path, not the filesystem,
# and switching a service to a dataset is a mount, not a migration.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kdn.containers;

  containerType = lib.types.submodule (
    { name, ... }:
    {
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
        stateDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          defaultText = lib.literalExpression ''"/var/lib/kdn/${name}"'';
          description = ''
            Host directory holding everything the container must keep, mounted at the same absolute
            path inside it and exported as `KDN_STATE_DIR`. Defaults to `/var/lib/kdn/<name>`.

            No other host path may carry state: a service that writes outside its state root breaks
            the backup contract.
          '';
        };
        stateDataset = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Fully qualified dataset, e.g. `tank/kdn/services/whisper`.";
                };
                refquota = lib.mkOption {
                  type = lib.types.str;
                  default = "20G";
                  description = ''
                    Quota on the dataset's own data. `refquota` rather than `quota` on purpose: a
                    snapshot must not consume the live filesystem's budget.
                  '';
                };
                compression = lib.mkOption {
                  type = lib.types.str;
                  default = "zstd";
                  description = "Compression algorithm for the dataset.";
                };
              };
            }
          );
          default = null;
          description = ''
            Declares the state root as a ZFS dataset instead of a plain directory. The dataset is
            created on demand with `mountpoint=<stateDir>`, `refquota`, `compression`, `atime=off`
            and `xattr=sa`, so the backup is `zfs snapshot` + `zfs send` and the restore is
            `zfs receive` + `nixos-rebuild switch`.
          '';
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
    }
  );

  # The state root is derived once here, so the volume, the dataset mountpoint, the tmpfiles rule
  # and `KDN_STATE_DIR` cannot drift apart.
  stateDirOf = name: c: if c.stateDir != null then c.stateDir else "/var/lib/kdn/${name}";

  # An explicit `volumes` entry for the state path wins: a container that wants its state root at
  # another path inside says so once, in `volumes`.
  volumesOf =
    name: c:
    {
      ${stateDirOf name c} = stateDirOf name c;
    }
    // c.volumes;

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
      # The state root is handed over twice: as the mount and as `KDN_STATE_DIR`, so a service
      # never has to hardcode the path it was given.
      ++ [ "-e KDN_STATE_DIR=${stateDirOf name c}" ]
      ++ lib.mapAttrsToList (h: v: "-v ${h}:${v}") (volumesOf name c)
      ++ c.extraArgs
      ++ [ "nix:0${c.image}" ]
      ++ c.cmd
      ++ c.args
    );

  # `zfs create` is the only way to make a dataset: NixOS mounts a declared filesystem but never
  # creates what is under it. The unit is `requiredBy` the container, so the state root exists and
  # is mounted before the first `nerdctl run`, and it re-mounts a dataset that exists but is
  # unmounted (a manual `zfs unmount`, a restore into a fresh pool).
  stateUnit = name: c: {
    description = "ZFS dataset for container ${name} state (${c.stateDataset.name})";
    requiredBy = [ "container-${name}.service" ];
    before = [ "container-${name}.service" ];
    # The mountpoint can sit inside a bind mount (an impermanent `/var/lib`), which local-fs
    # installs; mounting over a path that is not there yet fails.
    after = [ "local-fs.target" ];
    path = [
      config.boot.zfs.package
      pkgs.coreutils
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      stateDir=${lib.escapeShellArg (stateDirOf name c)}
      dataset=${lib.escapeShellArg c.stateDataset.name}
      mkdir -p "$stateDir"
      if ! zfs list -H -o name "$dataset" > /dev/null 2>&1; then
        zfs create -p \
          -o mountpoint="$stateDir" \
          -o compression=${c.stateDataset.compression} \
          -o atime=off \
          -o xattr=sa \
          -o refquota=${c.stateDataset.refquota} \
          "$dataset"
      fi
      mountpoint -q "$stateDir" || zfs mount "$dataset"
      # ZFS creates a mountpoint 0755; the plain-directory half of the contract is 0750
      # (systemd.tmpfiles.rules), so make both halves agree.
      chmod 0750 "$stateDir"
    '';
  };

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
    ) cfg.containers
    // lib.mapAttrs' (name: c: lib.nameValuePair "kdn-container-state-${name}" (stateUnit name c)) (
      lib.filterAttrs (_: c: c.stateDataset != null) cfg.containers
    );

    # The plain-directory half of the contract: a host without ZFS gets the same path as a
    # directory, created before the container starts.
    systemd.tmpfiles.rules = lib.mapAttrsToList (
      name: c: "d ${stateDirOf name c} 0750 root root -"
    ) cfg.containers;

    assertions = lib.mapAttrsToList (name: c: {
      assertion = c.stateDataset == null || config.boot.supportedFilesystems ? zfs;
      message = "kdn.containers.containers.${name}.stateDataset needs ZFS support, and boot.supportedFilesystems of this host does not list \"zfs\".";
    }) cfg.containers;

    environment.systemPackages = [ pkgs.nerdctl ];
    environment.extraInit = ''
      : "''${CONTAINERD_ADDRESS:=/run/containerd/containerd.sock}"
      : "''${CONTAINERD_SNAPSHOTTER:=nix}"
      export CONTAINERD_ADDRESS CONTAINERD_SNAPSHOTTER
    '';
  };
}

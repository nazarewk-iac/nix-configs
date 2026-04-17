# translated from NixOS https://github.com/NixOS/nixpkgs/blob/ac1acba43b2f9db073943ff5ed883ce7e8a40a2c/nixos/modules/virtualisation/containers.nix
{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.virtualisation.containers;
in
{
  options.kdn.virtualisation.containers = {
    enable = lib.mkEnableOption "container development setup";
    containersConf = {
      cniPlugins = lib.mkOption {
        type = with lib.types; listOf package;
        default = [ ];
        description = "CNI plugin packages";
      };
      settings = lib.mkOption {
        type = with lib.types; attrsOf anything;
        default = { };
        description = "containers.conf settings";
      };
    };
    storage = {
      settings = lib.mkOption {
        type = with lib.types; attrsOf anything;
        default = { };
        description = "storage.conf settings";
      };
    };
    registries = lib.mkOption {
      type = with lib.types; attrsOf (listOf anything);
      default = { };
      description = "Container registries configuration";
    };
    policy = lib.mkOption {
      type = with lib.types; attrsOf anything;
      default = { };
      description = "Container signature verification policy";
    };
    ociSeccompBpfHook = {
      enable = lib.mkEnableOption "OCI seccomp BPF hook";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      kdn.env.packages = with pkgs; [
        buildah
        buildkit
        dive
        skopeo
      ];
    })
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        kdn.virtualisation.containers.podman.enable = lib.mkDefault true;
        kdn.virtualisation.containers.docker.enable = lib.mkDefault (
          !config.kdn.virtualisation.containers.podman.enable
        );

        virtualisation.containers.storage.settings.storage.driver = lib.mkDefault "overlay";
        virtualisation.containers.storage.settings.storage.runroot =
          lib.mkDefault "/run/containers/storage";
        virtualisation.containers.storage.settings.storage.graphroot =
          lib.mkDefault "/var/lib/containers/storage";

        kdn.disks.persist."usr/cache".directories = [
          "/var/lib/containers/cache"
        ];
        kdn.disks.persist."usr/data".directories = [
          "/var/lib/containers/storage"
        ];
        home-manager.sharedModules = [
          {
            kdn.virtualisation.containers.enable = true;
          }
        ];
      }
    ))
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            kdn.virtualisation.containers.containersConf.cniPlugins = [ pkgs.cni-plugins ];
            kdn.virtualisation.containers.containersConf.settings = {
              network.cni_plugin_dirs = map (p: "${lib.getBin p}/bin") cfg.containersConf.cniPlugins;
              engine = {
                init_path = "${pkgs.catatonit}/bin/catatonit";
              }
              // lib.optionalAttrs cfg.ociSeccompBpfHook.enable {
                hooks_dir = [ config.boot.kernelPackages.oci-seccomp-bpf-hook ];
              };
            };
            # /home/kdn/.config/containers/storage.conf
            xdg.configFile."containers/containers.conf".source =
              (pkgs.formats.toml { }).generate "containers.conf"
                cfg.containersConf.settings;
            xdg.configFile."containers/storage.conf".source =
              (pkgs.formats.toml { }).generate "storage.conf"
                cfg.storage.settings;
            xdg.configFile."containers/registries.conf".source =
              (pkgs.formats.toml { }).generate "registries.conf"
                {
                  registries = lib.mapAttrs (n: v: { registries = v; }) cfg.registries;
                };
            xdg.configFile."containers/policy.json".source =
              if cfg.policy != { } then
                pkgs.writeText "policy.json" (builtins.toJSON cfg.policy)
              else
                "${pkgs.skopeo.policy}/default-policy.json";
          }
          { kdn.disks.persist."usr/data".directories = [ ".local/share/containers" ]; }
        ]
      )
    ))
  ];
}

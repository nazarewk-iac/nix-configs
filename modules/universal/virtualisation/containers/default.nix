{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.virtualisation.containers = {
            enable = lib.mkEnableOption "container development setup";
          };

  imports = [
    (
    # translated from NixOS https://github.com/NixOS/nixpkgs/blob/ac1acba43b2f9db073943ff5ed883ce7e8a40a2c/nixos/modules/virtualisation/containers.nix
    {
      lib,
      pkgs,
      config,
      kdnConfig,
      ...
    }:
      lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (
        let
          cfg = config.kdn.virtualisation.containers;

          inherit (lib) literalExpression mkOption types;

          toml = pkgs.formats.toml {};
        in {

config = kdnConfig.util.ifHM (lib.mkIf cfg.enable (
            lib.mkMerge [
              {
                kdn = {
                  virtualisation.containers.containersConf.cniPlugins = [pkgs.cni-plugins];

                  virtualisation.containers.containersConf.settings = {
                    network.cni_plugin_dirs = map (p: "${lib.getBin p}/bin") cfg.containersConf.cniPlugins;
                    engine =
                      {
                        init_path = "${pkgs.catatonit}/bin/catatonit";
                      }
                      // lib.optionalAttrs cfg.ociSeccompBpfHook.enable {
                        hooks_dir = [config.boot.kernelPackages.oci-seccomp-bpf-hook];
                      };
                  };
                };

                # /home/kdn/.config/containers/storage.conf
                xdg.configFile."containers/containers.conf".source =
                  toml.generate "containers.conf" cfg.containersConf.settings;

                xdg.configFile."containers/storage.conf".source = toml.generate "storage.conf" cfg.storage.settings;

                xdg.configFile."containers/registries.conf".source = toml.generate "registries.conf" {
                  registries = lib.mapAttrs (n: v: {registries = v;}) cfg.registries;
                };

                xdg.configFile."containers/policy.json".source =
                  if cfg.policy != {}
                  then pkgs.writeText "policy.json" (builtins.toJSON cfg.policy)
                  else "${pkgs.skopeo.policy}/default-policy.json";
              }
              {
                kdn.disks.persist."usr/data".directories = [
                  ".local/share/containers"
                ];
              }
            ]
          ));
        }
      )
    )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.virtualisation.containers;
        in {

          config = lib.mkIf cfg.enable {
            kdn.virtualisation.containers.podman.enable = lib.mkDefault true;
            kdn.virtualisation.containers.docker.enable = lib.mkDefault (!config.kdn.virtualisation.containers.podman.enable);

            virtualisation.containers.storage.settings.storage.driver = lib.mkDefault "overlay";
            virtualisation.containers.storage.settings.storage.runroot =
              lib.mkDefault "/run/containers/storage";
            virtualisation.containers.storage.settings.storage.graphroot =
              lib.mkDefault "/var/lib/containers/storage";

            environment.systemPackages = with pkgs; [
              buildah
              buildkit
              dive
              skopeo
            ];

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
          };
        }
      )
    )
  ];
}

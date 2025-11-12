# translated from NixOS https://github.com/NixOS/nixpkgs/blob/ac1acba43b2f9db073943ff5ed883ce7e8a40a2c/nixos/modules/virtualisation/containers.nix
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.virtualisation.containers;

  inherit (lib) literalExpression mkOption types;

  toml = pkgs.formats.toml {};
in {
  options.kdn.virtualisation.containers = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = lib.mdDoc ''
        This option enables the common ~/.config/containers configuration module.
      '';
    };

    ociSeccompBpfHook.enable = mkOption {
      type = types.bool;
      default = false;
      description = lib.mdDoc "Enable the OCI seccomp BPF hook";
    };

    containersConf.settings = mkOption {
      type = toml.type;
      default = {};
      description = lib.mdDoc "containers.conf configuration";
    };

    containersConf.cniPlugins = mkOption {
      type = types.listOf types.package;
      defaultText = literalExpression ''
        [
          pkgs.cni-plugins
        ]
      '';
      example = literalExpression ''
        [
          pkgs.cniPlugins.dnsname
        ]
      '';
      description = lib.mdDoc ''
        CNI plugins to install on the system.
      '';
    };

    storage.settings = mkOption {
      type = toml.type;
      default = {
        storage = {
          driver = "overlay";
        };
        storage.options.overlay = {
          mount_program = "${pkgs.fuse-overlayfs}/bin/fuse-overlayfs";
        };
      };
      description = lib.mdDoc "storage.conf configuration";
    };
    registries = {
      search = mkOption {
        type = types.listOf types.str;
        default = [
          "docker.io"
          "quay.io"
        ];
        description = lib.mdDoc ''
          List of repositories to search.
        '';
      };

      insecure = mkOption {
        default = [];
        type = types.listOf types.str;
        description = lib.mdDoc ''
          List of insecure repositories.
        '';
      };

      block = mkOption {
        default = [];
        type = types.listOf types.str;
        description = lib.mdDoc ''
          List of blocked repositories.
        '';
      };
    };

    policy = mkOption {
      default = {};
      type = types.attrs;
      example = literalExpression ''
        {
          default = [ { type = "insecureAcceptAnything"; } ];
          transports = {
            docker-daemon = {
              "" = [ { type = "insecureAcceptAnything"; } ];
            };
          };
        }
      '';
      description = lib.mdDoc ''
        Signature verification policy file.
        If this option is empty the default policy file from
        `skopeo` will be used.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
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
  );
}

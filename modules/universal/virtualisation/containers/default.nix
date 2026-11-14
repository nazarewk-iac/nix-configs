# translated from NixOS https://github.com/NixOS/nixpkgs/blob/ac1acba43b2f9db073943ff5ed883ce7e8a40a2c/nixos/modules/virtualisation/containers.nix
{

  lib,
  pkgs,
  config,
  kdnConfig,
  osConfig ? null,
  ...
}:
let
  cfg = config.kdn.virtualisation.containers;

  /*
    Home Manager runs standalone, or under a NixOS parent, or under a Darwin parent.
    `osConfig` is null in the standalone case, and it holds no `boot` option under a Darwin
    parent. The null test comes first, so neither `?` probe ever reads a null value.
  */
  hasOciHook = osConfig != null && osConfig ? boot && osConfig.boot ? kernelPackages;
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
      # Rootless podman reads its own store. It must not inherit the system paths below.
      # See the option description for the two measured traps: an empty file, and a `~` path.
      rootlessSettings = lib.mkOption {
        type = with lib.types; attrsOf anything;
        default = {
          storage = {
            driver = "overlay";
            graphroot = "$HOME/.local/share/containers/storage";
            runroot = "$XDG_RUNTIME_DIR/containers";
            options.overlay.mountopt = "nodev";
          };
        };
        description = ''
          The `storage.conf` settings of the per-user container store.

          The rootless engine reads this file first. Without it, the engine falls through to
          `/etc/containers/storage.conf.d/`, which names the root-owned system store, and every
          rootless command fails with `permission denied`.

          A path in this file expands `$HOME` and `$XDG_RUNTIME_DIR`, and expands no `~`. A
          `graphroot` of `~/.local/share/containers/storage` becomes a directory relative to the
          working directory (measured with podman 6.1.4 on 2026-11-14). Write `$HOME`.

          `pkgs.formats.toml` fails on a null value, so a consumer replaces a key with a real string
          and never clears one with `null`. The type is `attrsOf anything`, which does not merge, so
          an override at the leaf replaces the whole `storage` table: a consumer that writes
          `storage.graphroot` also states `driver` and `runroot`, or the rendered file loses them.
        '';
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
      lib.mkIf (cfg.enable && kdnConfig.util.hasParentOfAnyType [ "nixos" ]) (
        lib.mkMerge [
          {
            kdn.virtualisation.containers.containersConf.cniPlugins = [ pkgs.cni-plugins ];
            kdn.virtualisation.containers.containersConf.settings = {
              network.cni_plugin_dirs = map (p: "${lib.getBin p}/bin") cfg.containersConf.cniPlugins;
              engine = {
                init_path = "${pkgs.catatonit}/bin/catatonit";
              }
              // lib.optionalAttrs (cfg.ociSeccompBpfHook.enable && hasOciHook) {
                # A Home Manager module set holds no `boot` option. The value comes from the
                # parent, and `hasOciHook` proves the parent has one.
                hooks_dir = [ osConfig.boot.kernelPackages.oci-seccomp-bpf-hook ];
              };
            };
            # /home/kdn/.config/containers/containers.conf
            xdg.configFile."containers/containers.conf".source =
              (pkgs.formats.toml { }).generate "containers.conf"
                cfg.containersConf.settings;
            # /home/kdn/.config/containers/storage.conf
            xdg.configFile."containers/storage.conf".source =
              (pkgs.formats.toml { }).generate "storage.conf"
                cfg.storage.rootlessSettings;
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

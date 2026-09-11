# The shared container tooling, as a den aspect. It ports
# `modules/universal/virtualisation/containers/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs four image tools, it points the system container storage at the standard paths, and it
# renders four files under `~/.config/containers`: `containers.conf`, `storage.conf`,
# `registries.conf` and `policy.json`.
#
# ## It defaults no container engine on
#
# The old module turns podman on, or docker when podman is off. An aspect must not write another
# aspect's option, so the consumer includes `virt-containers-podman` or `virt-containers-docker`
# itself. Neither engine follows from this aspect any more.
#
# ## It reads no NixOS option from the home class — the fixed defect
#
# The old module reads `config.boot.kernelPackages.oci-seccomp-bpf-hook` inside its Home Manager
# branch. No Home Manager class declares a `boot` option, so that read is a hard error. Nix laziness
# hides it today, because no host forces that attribute path in the Home Manager context. A den
# aspect that forces every value makes the failure real.
#
# So the `homeManager` target below reads **no** NixOS option. The seccomp hook flag goes, and a
# plain `hooksDirs` list takes its place. A non-empty list is the switch, and the consumer states the
# directory. A NixOS consumer that wants the old behaviour writes one line in its host config:
#
#     kdn.virtualisation.containers.hooksDirs = [ config.boot.kernelPackages.oci-seccomp-bpf-hook ];
#
# A separate agent fixes the old tree. This file touches no `modules/universal/` file, so the two
# changes cannot collide.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`ociSeccompBpfHook.enable` goes.** See the paragraph above. Rule 2 forbids a reachable
#    `enable` option, so the flag could not survive in any case.
# 3. **`kdn.env.packages` does not survive.** Each target writes its own native option. Design B.
# 4. **The Home Manager forward goes.** A den consumer includes the aspect where it wants it.
# 5. **The home class needs Linux.** The old module runs the home branch only under a NixOS parent.
#    The `isLinux` test below is the den equivalent.
# 6. **The persist writes become output options.** See below.
#
# ## The persist directories become read-only outputs
#
#     # the nixos class
#     kdn.disks.persist."usr/cache".directories =
#       config.kdn.virtualisation.containers.persist.usrCache;
#     kdn.disks.persist."usr/data".directories =
#       config.kdn.virtualisation.containers.persist.usrData;
#
# The `homeManager` class publishes its own `persist.usrData`, relative to the home directory.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 2 above.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.virt-containers.nixos =
    {
      lib,
      pkgs,
      ...
    }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      options.kdn.virtualisation.containers.persist.usrCache = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The cache directories this aspect wants on persistent storage. The consumer wires the list
          into its own persistence option.
        '';
      };

      options.kdn.virtualisation.containers.persist.usrData = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The data directories this aspect wants on persistent storage. The consumer wires the list
          into its own persistence option.
        '';
      };

      config = {
        environment.systemPackages = filterPackages (
          with pkgs;
          [
            buildah
            buildkit
            dive
            skopeo
          ]
        );

        virtualisation.containers.storage.settings.storage.driver = lib.mkDefault "overlay";
        virtualisation.containers.storage.settings.storage.runroot =
          lib.mkDefault "/run/containers/storage";
        virtualisation.containers.storage.settings.storage.graphroot =
          lib.mkDefault "/var/lib/containers/storage";

        kdn.virtualisation.containers.persist.usrCache = [
          "/var/lib/containers/cache"
        ];
        kdn.virtualisation.containers.persist.usrData = [
          "/var/lib/containers/storage"
        ];
      };
    };

  kdn.virt-containers.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.virtualisation.containers;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      options.kdn.virtualisation.containers.containersConf.cniPlugins = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "The CNI plugin packages the container engine loads.";
      };

      options.kdn.virtualisation.containers.containersConf.settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "The `containers.conf` settings.";
      };

      options.kdn.virtualisation.containers.storage.settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = "The `storage.conf` settings.";
      };

      options.kdn.virtualisation.containers.registries = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.anything);
        default = { };
        description = "The `registries.conf` registry lists, one list per kind.";
      };

      options.kdn.virtualisation.containers.policy = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          The image signature policy. An empty set keeps the `skopeo` default policy.
        '';
      };

      options.kdn.virtualisation.containers.hooksDirs = lib.mkOption {
        type = lib.types.listOf (lib.types.either lib.types.str lib.types.package);
        default = [ ];
        example = lib.literalExpression "[ config.boot.kernelPackages.oci-seccomp-bpf-hook ]";
        description = ''
          The directories the container engine searches for an OCI hook. An empty list writes no
          `hooks_dir` key.

          A non-empty list is the switch, so this aspect needs no flag. The consumer states the
          directory, so this target reads no option of another class.
        '';
      };

      options.kdn.virtualisation.containers.persist.usrData = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The data directories this aspect wants on persistent storage, relative to the home
          directory. The consumer wires the list into its own persistence option.
        '';
      };

      config = lib.mkMerge [
        {
          kdn.virtualisation.containers.persist.usrData = [ ".local/share/containers" ];
        }
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          home.packages = filterPackages (
            with pkgs;
            [
              buildah
              buildkit
              dive
              skopeo
            ]
          );

          kdn.virtualisation.containers.containersConf.cniPlugins = [ pkgs.cni-plugins ];
          kdn.virtualisation.containers.containersConf.settings = {
            network.cni_plugin_dirs = map (p: "${lib.getBin p}/bin") cfg.containersConf.cniPlugins;
            engine = {
              init_path = "${pkgs.catatonit}/bin/catatonit";
            }
            // lib.optionalAttrs (cfg.hooksDirs != [ ]) {
              hooks_dir = cfg.hooksDirs;
            };
          };

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
        })
      ];
    };
}

# The shared container tooling, as a den aspect. It ports
# `modules/universal/virtualisation/containers/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs four image tools, it points the system container storage at the standard paths, and it
# renders five files under `~/.config/containers`: `containers.conf`, `storage.conf`,
# `storage.conf.d/99-user.conf`, `registries.conf` and `policy.json`. The drop-in is the layer that
# beats `/etc/containers/storage.conf.d/00-nixos.conf` — c/storage merges every `*.conf` in
# file-name order, last writer wins per key, so `50-user.conf` won only by sorting late.
#
# A root Home Manager profile renders none of them. A privileged `podman` reads `/etc/containers/`,
# and the per-user paths collapse under `sudo` (`runroot` becomes `/containers` at the filesystem
# root), so the file block is gated on a non-root `home.username`.
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

      /*
        c/storage merges every `*.conf` file of every `storage.conf.d` directory on the search
        path in file-name order, and the last file to set a key wins. The directory does not
        establish precedence, so this name is load-bearing: it must sort after
        `/etc/containers/storage.conf.d/00-nixos.conf`.
      */
      dropinName = "99-user.conf";
      dropinPath = "containers/storage.conf.d/${dropinName}";
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
        description = ''
          The `storage.conf` settings of the per-user container store.

          The rootless engine reads this file, and it then merges every `storage.conf.d/*.conf` on
          the search path in file-name order, last writer wins per key. The deciding layer is the
          drop-in this aspect renders to `~/.config/containers/storage.conf.d/99-user.conf`, not
          this file: `/etc/containers/storage.conf.d/00-nixos.conf` names the root-only store.

          A path in this file expands `$HOME` and `$XDG_RUNTIME_DIR`, and expands no `~`. A
          `graphroot` of `~/.local/share/containers/storage` becomes a directory relative to the
          working directory (measured with podman 6.1.4 on 2026-11-14). Write `$HOME`.

          `pkgs.formats.toml` fails on a null value, so a consumer replaces a key with a real string
          and never clears one with `null`. The type is `attrsOf anything`, which does not merge, so
          an override at the leaf replaces the whole `storage` table: a consumer that writes
          `storage.graphroot` also states `driver` and `runroot`, or the rendered file loses them.
        '';
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

          This list names no persistence bucket. The old universal containers module writes the
          same directory into the bucket its `storage.rootlessPersistBase` option names (`usr/data`
          by default, `null` to write nothing), so the bucket stays a decision of the NixOS consumer
          here too. See `docs/den-universal-mapping.md`.
        '';
      };

      config = lib.mkMerge [
        {
          kdn.virtualisation.containers.persist.usrData = [ ".local/share/containers" ];

          # The rootless engine reads this file before the system drop-ins. Without it, the
          # engine takes `graphroot` and `runroot` from
          # `/etc/containers/storage.conf.d/00-nixos.conf`, which names the root-only store at
          # `/var/lib/containers/storage`, and every rootless command fails with
          # `mkdir /var/lib/containers/storage/libpod: permission denied`. `$HOME` and
          # `$XDG_RUNTIME_DIR` expand per user, so one file serves every user of the host. A `~`
          # does NOT expand here: it becomes a directory relative to the working directory
          # (measured with podman 6.1.4 on 2026-11-14).
          kdn.virtualisation.containers.storage.settings = lib.mkDefault {
            storage = {
              driver = "overlay";
              graphroot = "$HOME/.local/share/containers/storage";
              runroot = "$XDG_RUNTIME_DIR/containers";
              options.overlay.mountopt = "nodev";
            };
          };
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
        })
        # Root keeps the system store. A privileged `podman` reads `/etc/containers/`, and a root
        # Home Manager profile would otherwise render the per-user files below for it too: the
        # `$HOME`/`$XDG_RUNTIME_DIR` paths then collapse (`sudo` sets no `XDG_RUNTIME_DIR`, so
        # `runroot` becomes `/containers` at the filesystem root), and the rootful engine abandons
        # `/var/lib/containers/storage`. Measured on both hosts with podman 6.1.4 on 2026-11-14.
        (lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && config.home.username != "root") {
          xdg.configFile."containers/containers.conf".source =
            (pkgs.formats.toml { }).generate "containers.conf"
              cfg.containersConf.settings;
          xdg.configFile."containers/storage.conf".source =
            (pkgs.formats.toml { }).generate "storage.conf"
              cfg.storage.settings;
          # c/storage merges every `*.conf` of every `storage.conf.d` directory on the search path
          # in one pass, **in file-name order**, and the last file to set a key wins. The directory
          # does not establish precedence: a user drop-in named `00-aaa.conf` loses to
          # `/etc/containers/storage.conf.d/00-nixos.conf`, and one named `99-user.conf` wins
          # (measured with podman 6.1.4 on 2026-11-14). The NixOS drop-in names the root-only
          # `/var/lib/containers/storage`, so the user `storage.conf` above loses to it, and this
          # file's number is what beats it. A future `/etc` or `/usr/share` drop-in named above
          # `99-` wins in turn.
          #
          # The base `storage.conf` is still read: only the keys a later file sets are replaced,
          # so a base-file-only key survives the merge. Rendering the same settings twice is
          # deliberate: `buildah` and `skopeo` work through the base file, and only the drop-in
          # beats `/etc`.
          xdg.configFile.${dropinPath}.source =
            (pkgs.formats.toml { }).generate dropinName
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

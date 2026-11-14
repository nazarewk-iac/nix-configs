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

  /*
    c/storage merges every `*.conf` file of every `storage.conf.d` directory in file-name order,
    and the last file to set a key wins. The directory does not establish precedence, so this
    name decides which layer wins: it must sort after `/etc/containers/storage.conf.d/
    00-nixos.conf`. Defined once, because a rename is otherwise four edits.
  */
  dropinName = "99-user.conf";
  dropinPath = "containers/storage.conf.d/${dropinName}";
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

          The rootless engine reads the user `storage.conf`, and it then merges every
          `storage.conf.d/*.conf` file on the search path in file-name order, last writer wins
          per key. `/etc/containers/storage.conf.d/00-nixos.conf` names the root-owned system
          store, so this file alone loses to it. The deciding layer is the drop-in this module
          renders to `~/.config/containers/storage.conf.d/99-user.conf`, not this file.

          `runroot` is redundant on its own (c/storage already defaults it to
          `$XDG_RUNTIME_DIR/containers`). It is stated here to beat `00-nixos.conf`, so do not
          delete it as dead weight.

          A path in this file expands `$HOME` and `$XDG_RUNTIME_DIR`, and expands no `~`. A
          `graphroot` of `~/.local/share/containers/storage` becomes a directory relative to the
          working directory (measured with podman 6.1.4 on 2026-11-14). Write `$HOME`.

          `pkgs.formats.toml` fails on a null value, so a consumer replaces a key with a real string
          and never clears one with `null`. The type is `attrsOf anything`, which does not merge, so
          an override at the leaf replaces the whole `storage` table: a consumer that writes
          `storage.graphroot` also states `driver` and `runroot`, or the rendered file loses them.
        '';
      };
      # The `kdn.disks.persist` bucket that backs the home-relative rootless container store.
      # `null` disables the write for a host whose home is already persistent.
      rootlessPersistBase = lib.mkOption {
        type = with lib.types; nullOr str;
        default = "usr/data";
        description = ''
          The `kdn.disks.persist` bucket that backs the home-relative rootless container store
          (`~/.local/share/containers`). `null` disables the persist write for a host whose home
          already lives on a persistent dataset (oams: `fs/home/kdn/.local/share/containers` is
          its own ZFS dataset). The value must name a `kdn.disks.base` entry (`usr/data`, ...),
          and a NixOS assertion holds it to that: a bucket that no base declares produces an
          empty `preservation.preserveAt` entry, so a typo would disable the write in silence.

          Do not name `disposable`: that base is wiped at every boot, so the container store
          there would be lost.
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
        # The bucket name is read in this NixOS context and passed to Home Manager as a literal
        # key. Reading it inside the Home Manager module forces that module's own config during
        # evaluation, and the dynamic key re-enters it: `error: infinite recursion encountered`.
        # The key is substituted before `kdn.disks.persist` is evaluated, so no read remains.
        home-manager.sharedModules = [
          {
            kdn.virtualisation.containers.enable = true;
          }
          (lib.optionalAttrs (cfg.storage.rootlessPersistBase != null) {
            kdn.disks.persist.${cfg.storage.rootlessPersistBase}.directories = [
              ".local/share/containers"
            ];
          })
        ];

        /*
          A bucket that `kdn.disks.base` does not declare is inert: `disks/config.nix` builds
          `preservation.preserveAt` from the base names alone, so the write lands in a bucket that
          no base reads, and the store silently stops being preserved. `nullOr str` accepts any
          string, hence this assertion. `kdn.disks.base` may be absent or shifted in another
          module set (a den target or an adopter), so the probe tests the option first.
        */
        assertions =
          let
            base = config.kdn.disks.base or null;
            persistBase = cfg.storage.rootlessPersistBase;
          in
          [
            {
              assertion = persistBase == null || base == null || base ? ${persistBase};
              message = ''
                kdn.virtualisation.containers.storage.rootlessPersistBase is "${toString persistBase}",
                which is not a `kdn.disks.base` bucket. Known buckets:
                ${lib.concatStringsSep ", " (builtins.attrNames (if base == null then { } else base))}.
                A bucket that no base declares never reaches `preservation.preserveAt`, so the
                rootless container store would not be preserved. Use `null` for a host whose home
                is already persistent.
              '';
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
          }
          # Root keeps the system store. A privileged `podman` reads `/etc/containers/`, and a
          # root Home Manager profile would otherwise render the per-user files below for it too:
          # the `$HOME`/`$XDG_RUNTIME_DIR` paths then collapse (`sudo` sets no
          # `XDG_RUNTIME_DIR`, so `runroot` becomes `/containers` at the filesystem root), and the
          # rootful engine abandons `/var/lib/containers/storage`. Measured on both hosts with
          # podman 6.1.4 on 2026-11-14. `home.username` is a Home Manager option, and this block
          # runs in the Home Manager class only.
          (lib.mkIf (config.home.username != "root") {
            # /home/kdn/.config/containers/containers.conf
            xdg.configFile."containers/containers.conf".source =
              (pkgs.formats.toml { }).generate "containers.conf"
                cfg.containersConf.settings;
            # /home/kdn/.config/containers/storage.conf
            xdg.configFile."containers/storage.conf".source =
              (pkgs.formats.toml { }).generate "storage.conf"
                cfg.storage.rootlessSettings;
            # /home/kdn/.config/containers/storage.conf.d/99-user.conf
            #
            # c/storage merges every `*.conf` of every `storage.conf.d` directory on the search
            # path in one pass, **in file-name order**, and the last file to set a key wins. The
            # directory does not establish precedence: a user drop-in named `00-aaa.conf` loses
            # to `/etc/containers/storage.conf.d/00-nixos.conf`, and one named `99-user.conf`
            # wins (measured with podman 6.1.4 on 2026-11-14). The NixOS drop-in names the
            # root-only `/var/lib/containers/storage`, so the user `storage.conf` above loses to
            # it, and this file's number is what beats it. A future `/etc` or `/usr/share`
            # drop-in named above `99-` wins in turn.
            #
            # The base `storage.conf` is still read: only the keys a later file sets are
            # replaced, so a base-file-only key survives the merge. Rendering the same settings
            # twice is deliberate: `buildah` and `skopeo` work through the base file, and only
            # the drop-in beats `/etc`.
            xdg.configFile.${dropinPath}.source =
              (pkgs.formats.toml { }).generate dropinName
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
          })
        ]
      )
    ))
  ];
}

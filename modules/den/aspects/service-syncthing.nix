# Syncthing file synchronization, as a den aspect. It ports
# `modules/universal/services/syncthing/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs Syncthing as a user service, with the configuration under `XDG_CONFIG_HOME` and the data
# under `XDG_DATA_HOME`. It turns the tray icon off.
#
# ## The web interface keeps the Syncthing default
#
# The old module passes `--gui-address` with a literal value. Syncthing already binds the loopback
# interface by itself, so this aspect passes the flag only when the consumer names an address in
# `guiAddress`. So the aspect states no address of its own.
#
# ## One class only
#
# The old module runs the service in the Home Manager context, and only when the parent is NixOS.
# So this aspect serves the `homeManager` class only, and the whole target sits behind an
# `isLinux` test: Syncthing needs a systemd user service, and a darwin home has none.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The Home Manager forward goes.** A den consumer includes the aspect where it wants it.
# 3. **`kdn.env.packages` does not survive.** The target writes `home.packages`. Design B. The old
#    module installs `stc-cli` in both contexts; the home context keeps it here.
# 4. **The persist writes become output options.** See below.
#
# ## The persist directories become read-only outputs
#
# The old module writes two `kdn.disks.persist.*` buckets. An aspect must not write another aspect's
# option, so this aspect publishes two lists and the consumer wires them:
#
#     kdn.disks.persist."usr/data".directories = config.kdn.services.syncthing.persist.usrData;
#     kdn.disks.persist."usr/config".directories = config.kdn.services.syncthing.persist.usrConfig;
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.service-syncthing.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.services.syncthing;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      # One generated ignore file per folder: the common patterns plus the per-host include.
      # `.stignore` symlinks to this store path; the include file is the host's.
      commonIgnore = pkgs.writeText "kdn-stignore" (
        lib.concatStringsSep "\n" cfg.ignorePatterns + "\n#include .stignore.local\n"
      );
    in
    {
      options.kdn.services.syncthing.guiAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The address the web interface binds, as `<host>:<port>`. `null` keeps the Syncthing
          default, which is the loopback interface.
        '';
      };

      options.kdn.services.syncthing.devices = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Peer devices, as `<name> = <device id>`. The host passes the peers of its shares; the
          device IDs come from `stc id` on the peer.
        '';
      };

      options.kdn.services.syncthing.shares = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        description = ''
          The shares this host holds, as `<share> = [ <peer names> ]`. Each share becomes one
          Syncthing folder at `~/.local/share/kdn/synced/<share>`, shared with the named peers.
        '';
      };

      options.kdn.services.syncthing.ignorePatterns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          # Agent journals and boards are handover data; keep them although they live under
          # `.cache`. The negations must precede the broad ignore: the first match wins.
          "!**/.cache/agents"
          "!**/.cache/agents/**"
          "**/.cache/*"
          # Build outputs and caches: rebuilt on each host, never synced.
          "**/.devenv"
          "**/.direnv"
          "**/result"
          "**/result-*"
          "**/node_modules"
          "**/target"
          "**/dist"
          "**/build"
          "**/.next"
          "**/.nuxt"
          "**/.svelte-kit"
          "**/.turbo"
          "**/.parcel-cache"
          "**/.gradle"
          "**/.zig-cache"
          "**/zig-out"
          "**/__pycache__"
          "**/*.pyc"
          "**/.pytest_cache"
          "**/.mypy_cache"
          "**/.ruff_cache"
          # jj rewrites these while a command runs; a scan can catch a file that is already gone.
          # The VCS state is carried between machines on purpose; never ignore .git/.jj.
          # The per-host include file is the one thing that must stay local.
          ".stignore.local"
          ".stignore-*"
        ];
        description = ''
          Common `.stignore` patterns, written into every share and `~/dev` on activation.
          Host one-offs belong in `~/.stignore-<host>` and are appended there; this list must
          stay host-neutral.
        '';
      };

      options.kdn.services.syncthing.persist.usrData = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The data directories this aspect wants on persistent storage, relative to the home
          directory. The consumer wires the list into its own persistence option.
        '';
      };

      options.kdn.services.syncthing.persist.usrConfig = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The configuration directories this aspect wants on persistent storage, relative to the
          home directory. The consumer wires the list into its own persistence option.
        '';
      };

      config = lib.mkMerge [
        {
          kdn.services.syncthing.persist.usrData = [
            ".local/share/syncthing"
            ".local/share/kdn/synced"
          ];
          kdn.services.syncthing.persist.usrConfig = [
            ".config/syncthing"
          ];
        }
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          home.packages = filterPackages [ pkgs.stc-cli ];

          services.syncthing.enable = true;
          # Additive: the pre-existing `~/dev` folder and its device pairing stay untouched.
          services.syncthing.overrideDevices = false;
          services.syncthing.overrideFolders = false;
          services.syncthing.settings = {
            devices = lib.mapAttrs (_: id: { inherit id; }) cfg.devices;
            folders = lib.mapAttrs (share: peers: {
              enable = true;
              path = "${config.xdg.dataHome}/kdn/synced/${share}";
              label = "kdn/${share}";
              type = "sendreceive";
              devices = peers;
            }) cfg.shares;
          };
          # The common patterns are one store file; every folder's `.stignore` is a symlink to it,
          # and the store file `#include`s `.stignore.local` for the non-managed host one-offs.
          # `.stignore.local` is ignored (so it never travels); the `.stignore` itself is never
          # synced by Syncthing.
          # The user-wide copy: the same patterns, independent of any share, for reference and
          # for tools outside Syncthing. The per-folder `.stignore` symlinks duplicate it by
          # design; the store file adds the `.stignore.local` include.
          home.file.".config/kdn/syncthing/ignore-common".text =
            lib.concatStringsSep "\n" cfg.ignorePatterns + "\n";
          home.activation.syncthing-ignores = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            for folder in ${
              lib.concatMapStringsSep " " (share: "\"$HOME/.local/share/kdn/synced/${share}\"") (
                lib.attrNames cfg.shares
              )
            } "$HOME/dev"; do
              [ -d "$folder" ] || continue
              ln -sfn ${commonIgnore} "$folder/.stignore"
              { for f in "$folder"/.stignore-*; do [ -f "$f" ] && cat "$f"; done; } > "$folder/.stignore.local"
            done
          '';

          # Syncthing refuses a pre-created empty folder without its `.stfolder` marker, and it
          # treats a missing path as an error. Create the share roots and the markers during
          # activation, so a fresh host starts clean.
          home.activation.syncthing-share-markers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            for share in ${lib.concatStringsSep " " (lib.attrNames cfg.shares)}; do
              mkdir -p "$HOME/.local/share/kdn/synced/$share/.stfolder"
            done
          '';
          services.syncthing.extraOptions = [
            # see https://docs.syncthing.net/users/syncthing.html
            "--config=${config.xdg.configHome}/syncthing"
            "--data=${config.xdg.dataHome}/syncthing"
            "--auditfile=--"
          ]
          ++ lib.optional (cfg.guiAddress != null) "--gui-address=${cfg.guiAddress}";
          services.syncthing.tray.enable = false;

          systemd.user.services.syncthing.Unit.After = [ "paths.target" ];
        })
      ];
    };
}

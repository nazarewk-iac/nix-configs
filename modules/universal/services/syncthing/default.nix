{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.services.syncthing;

  # One generated ignore file per folder: the common patterns plus the per-host include.
  # `.stignore` symlinks to this store path; the include file is the host's.
  commonIgnore = pkgs.writeText "kdn-stignore" (
    lib.concatStringsSep "\n" cfg.ignorePatterns + "\n#include .stignore.local\n"
  );
in
{
  options.kdn.services.syncthing = {
    enable = lib.mkEnableOption "Syncthing file synchronization";
    devices = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Peer devices, as `<name> = <device id>`.";
    };
    shares = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      description = "The shares this host holds, as `<share> = [ <peer names> ]`.";
    };
    ignorePatterns = lib.mkOption {
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
      description = "Common `.stignore` patterns; host one-offs go in `~/.stignore-<host>`.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          stc-cli
        ];
      }
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.services.syncthing = lib.mkDefault cfg; } ];
      })
      (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) {
        services.syncthing.enable = true;
        services.syncthing.extraOptions = [
          # see https://docs.syncthing.net/users/syncthing.html
          "--config=${config.xdg.configHome}/syncthing"
          "--data=${config.xdg.dataHome}/syncthing"
          "--auditfile=--"
          "--gui-address=127.0.0.1:8384"
        ];
        services.syncthing.tray.enable = false;
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
        # Syncthing refuses an empty pre-created folder without its `.stfolder` marker.
        home.activation.syncthing-share-markers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          for share in ${lib.concatStringsSep " " (lib.attrNames cfg.shares)}; do
            mkdir -p "$HOME/.local/share/kdn/synced/$share/.stfolder"
          done
        '';
        # The common patterns are one store file; every folder's `.stignore` is a symlink to it,
        # and the store file `#include`s `.stignore.local` for the non-managed host one-offs.
        # `.stignore.local` is ignored (so it never travels); the `.stignore` itself is never
        # synced by Syncthing.
        # The user-wide copy: the same patterns, independent of any share, for reference and for
        # tools outside Syncthing. The per-folder `.stignore` symlinks duplicate it by design;
        # the store file adds the `.stignore.local` include.
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
        kdn.disks.persist."usr/data".directories = [
          ".local/share/syncthing"
          ".local/share/kdn/synced"
        ];
        kdn.disks.persist."usr/config".directories = [
          ".config/syncthing"
        ];

        systemd.user.services.syncthing = {
          Unit.After = [ "paths.target" ];
        };
      })
    ]
  );
}

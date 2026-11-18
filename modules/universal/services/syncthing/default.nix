{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.services.syncthing;
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

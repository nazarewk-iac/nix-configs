{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.toolset.fs;
in
{
  options.kdn.toolset.fs = {
    enable = lib.mkEnableOption "linux utils";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent { home-manager.sharedModules = [ { kdn.toolset.fs = cfg; } ]; })
    (lib.mkIf cfg.enable {
      kdn.programs.midnight-commander.enable = lib.mkDefault true;
      kdn.env.packages =
        with pkgs;
        (
          [
            bintools
            file
            ncdu
            tree
          ]
          ++ [
            entr # run commands on changes https://eradman.com/entrproject/
            fswatch # cross-platform equivalent of inotify-tools ?
            watchexec
            # watchman # TODO: didn't build on 2026-02-12
          ]
          ++ [
            # flashing etc.
            # TODO: didn't find any GUI flashing tool yet
          ]
        );
    })
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        programs.yazi.enable = true;
        programs.yazi.enableFishIntegration = true;
        programs.yazi.enableZshIntegration = true;
      }
    ))
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        kdn.env.packages =
          with pkgs;
          [
            inotify-info
            inotify-tools
          ]
          ++ [
            # formatting etc.
            # exfat # this is FUSE implementation https://github.com/relan/exfat
            dosfstools
            exfatprogs # this is userspace util for linux 5.7+ kernel module for exfat https://github.com/exfatprogs/exfatprogs
            gptfdisk
            ntfs3g
          ];
      }
    ))
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { kdn.toolset.fs.enable = true; } ];

        kdn.toolset.tracing.enable = lib.mkDefault true;
        kdn.toolset.fs.encryption.enable = lib.mkDefault true;
      }
    ))
  ];
}

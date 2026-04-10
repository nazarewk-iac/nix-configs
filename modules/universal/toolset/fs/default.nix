{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.toolset.fs = {
            enable = lib.mkEnableOption "linux utils";
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.toolset.fs;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable {
            kdn.programs.midnight-commander.enable = lib.mkDefault true;

            home.packages = with pkgs; (
              [
                bintools
                file
                ncdu
                tree
              ]
              ++ [
                entr # run commands on changes https://eradman.com/entrproject/
                fswatch # cross-platform equivalent of inotify-tools ?
                inotify-info
                inotify-tools
                watchexec
                # watchman # TODO: didn't build on 2026-02-12
              ]
              ++ [
                # formatting etc.
                # exfat # this is FUSE implementation https://github.com/relan/exfat
                dosfstools
                exfatprogs # this is userspace util for linux 5.7+ kernel module for exfat https://github.com/exfatprogs/exfatprogs
                gptfdisk
                ntfs3g
              ]
              ++ [
                # flashing etc.
                # TODO: didn't find any GUI flashing tool yet
              ]
            );
          }));
        }
      )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.toolset.fs;
        in {

          config = lib.mkIf cfg.enable {
            home-manager.sharedModules = [{kdn.toolset.fs.enable = true;}];

            kdn.toolset.tracing.enable = lib.mkDefault true;
            kdn.toolset.fs.encryption.enable = lib.mkDefault true;
          };
        }
      )
    )
  ];
}

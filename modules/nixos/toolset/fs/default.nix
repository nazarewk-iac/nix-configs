{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.toolset.fs;
in
{
  options.kdn.toolset.fs = {
    enable = lib.mkEnableOption "linux utils";
  };

  config = lib.mkIf cfg.enable {
    kdn.toolset.tracing.enable = lib.mkDefault true;
    kdn.toolset.fs.encryption.enable = lib.mkDefault true;
    environment.systemPackages =
      with pkgs;
      (
        [
          bintools
          file
          ncdu
          tree
          mc # midnight commander
        ]
        ++ [
          entr # run commands on changes https://eradman.com/entrproject/
          fswatch # cross-platform equivalent of inotify-tools ?
          inotify-info
          inotify-tools
          watchexec
          watchman
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
  };
}

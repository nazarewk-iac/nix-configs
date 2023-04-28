{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.filesystems.base;
in
{
  options.kdn.filesystems.base = {
    enable = lib.mkEnableOption "basic filesystems related setup";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      dosfstools
      ntfs3g
      gptfdisk
      util-linux
      # exfat # this is FUSE implementation https://github.com/relan/exfat
      exfatprogs # this is userspace util for linux 5.7+ kernel module for exfat https://github.com/exfatprogs/exfatprogs
    ];
  };
}

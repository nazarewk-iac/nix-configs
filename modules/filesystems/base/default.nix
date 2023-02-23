{ lib, pkgs, config, ... }:
with lib;
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
      exfat
      exfatprogs
    ];
  };
}

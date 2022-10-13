{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.filesystems.base;
in
{
  options.kdn.filesystems.base = {
    enable = mkEnableOption "basic filesystems related setup";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      dosfstools
      ntfs3g
      gptfdisk
      util-linux
      exfat
    ];
  };
}

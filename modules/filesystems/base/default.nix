{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.filesystems.base;
in
{
  options.nazarewk.filesystems.base = {
    enable = mkEnableOption "basic filesystems related setup";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      dosfstools
      ntfs3g
      gptfdisk
      util-linux
      exfat-utils
    ];
  };
}

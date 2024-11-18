{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.android;
in {
  options.kdn.development.android = {
    enable = lib.mkEnableOption "working with Android devices";
  };

  config = lib.mkIf cfg.enable {
    programs.adb.enable = true;
    environment.systemPackages = with pkgs; [
      android-tools
    ];
    services.udev.packages = [
      pkgs.android-udev-rules
    ];
  };
}

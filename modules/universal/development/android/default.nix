{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.android;
in
{
  options.kdn.development.android = {
    enable = lib.mkEnableOption "working with Android devices";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          android-tools
        ];
      }
      (kdnConfig.util.ifTypes [ "nixos" ] {
        services.udev.packages = [
          # pkgs.android-udev-rules # superseded by built-in rules
        ];
      })
    ]
  );
}

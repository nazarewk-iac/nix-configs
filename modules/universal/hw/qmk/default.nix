{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.hw.qmk;
in
{
  options = {
    kdn.hw.qmk = {
      enable = lib.mkEnableOption "QMK + ZSA keyboard related software (eg: Moonlander)";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          keymapviz
          qmk
          wally-cli

          (pkgs.writeShellApplication {
            name = "oryx-flash";
            runtimeInputs = with pkgs; [
              wally-cli
              curl
            ];
            text = builtins.readFile ./oryx-flash.sh;
          })

          (pkgs.writeShellApplication {
            name = "oryx-src";
            runtimeInputs = with pkgs; [
              curl
              unzip
            ];
            text = builtins.readFile ./oryx-src.sh;
          })
        ];
      }
      (kdnConfig.util.ifTypes [ "nixos" ] (
        lib.mkMerge [
          {
            services.udev.packages = with pkgs; [
              qmk-udev-rules
              zsa-udev-rules
            ];
          }
          (lib.mkIf config.kdn.desktop.enable {
            kdn.env.packages = with pkgs; [
              vial
            ];
          })
        ]
      ))
    ]
  );
}

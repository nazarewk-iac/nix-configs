{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.hardware.qmk;
in
{
  options = {
    nazarewk.hardware.qmk = {
      enable = mkEnableOption "QMK keyboard related software (eg: Moonlander)";
    };
  };

  config = mkIf cfg.enable (mkMerge [{
    environment.systemPackages = with pkgs; [
      keymapviz
      qmk
      qmk-udev-rules
      wally-cli
    ];
  }
    (mkIf config.nazarewk.headless.enableGUI {
      environment.systemPackages = with pkgs; [
        vial
      ];
    })]);
}

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

      (pkgs.writeShellApplication {
        name = "oryx-flash";
        runtimeInputs = with pkgs; [ wally-cli curl ];
        text = builtins.readFile ./oryx-flash.sh;
      })

      (pkgs.writeShellApplication {
        name = "oryx-src";
        runtimeInputs = with pkgs; [ curl unzip ];
        text = builtins.readFile ./oryx-src.sh;
      })
    ];
  }
    (mkIf config.nazarewk.headless.enableGUI {
      environment.systemPackages = with pkgs; [
        vial
      ];
    })]);
}

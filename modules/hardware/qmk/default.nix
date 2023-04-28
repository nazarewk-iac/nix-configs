{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.qmk;
in
{
  options = {
    kdn.hardware.qmk = {
      enable = lib.mkEnableOption "QMK + ZSA keyboard related software (eg: Moonlander)";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [{
    services.udev.packages = with pkgs; [
      qmk-udev-rules
      zsa-udev-rules
    ];

    environment.systemPackages = with pkgs; [
      keymapviz
      qmk
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
    (lib.mkIf config.kdn.headless.enableGUI {
      environment.systemPackages = with pkgs; [
        vial
      ];
    })]);
}

{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.profile.machine.desktop;
in
{
  options.kdn.profile.machine.desktop = {
    enable = lib.mkEnableOption "enable desktop machine profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.basic.enable = true;

    kdn.sway.gdm.enable = true;
    kdn.sway.systemd.enable = true;

    kdn.headless.enableGUI = true;

    boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
    boot.binfmt.emulatedSystems = [
      "aarch64-linux"
      "wasm32-wasi"
      "wasm64-wasi"
      "x86_64-windows"
    ];

    # Enable CUPS to print documents.
    services.printing.enable = true;
    services.printing.drivers = with pkgs; [
      hplip
      gutenprint
      gutenprintBin
      brlaser
      brgenml1lpr
      brgenml1cupswrapper
    ];
    programs.seahorse.enable = true;

    kdn.containers.dagger.enable = true;
    kdn.emulators.windows.enable = true;
  };
}

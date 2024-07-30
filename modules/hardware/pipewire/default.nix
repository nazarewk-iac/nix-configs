{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.pipewire;
in
{
  options = {
    kdn.hardware.pipewire = {
      enable = lib.mkEnableOption "Pipewire setup";

      useWireplumber = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # SOUND - PipeWire
      # see additional pavucontrol package
      security.rtkit.enable = true;
      hardware.pulseaudio.enable = false;
      services.pipewire.enable = true;

      services.pipewire.alsa.enable = true;
      services.pipewire.alsa.support32Bit = true;
      services.pipewire.jack.enable = true;
      services.pipewire.pulse.enable = true;
      services.pipewire.wireplumber.enable = cfg.useWireplumber;

      hardware.pulseaudio.extraModules = [
        pkgs.pulseaudio-modules-bt
      ];

      hardware.bluetooth.package = pkgs.bluez5-experimental;
    }
    (lib.mkIf config.kdn.headless.enableGUI {
      environment.systemPackages = with pkgs; [
        pavucontrol
        pulseaudio # pactl
        helvum # A GTK patchbay for pipewire
      ];
      home-manager.sharedModules = [{
        #services.easyeffects.enable = true;
      }];
      # required by easyeffects
      programs.dconf.enable = true;
    })
  ]);
}

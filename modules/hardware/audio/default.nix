{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.audio;
in
{
  options = {
    kdn.hardware.audio = {
      enable = lib.mkEnableOption "audio setup with Pipewire";
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
      services.pipewire.wireplumber.enable = true;

      hardware.pulseaudio.extraModules = [
        pkgs.pulseaudio-modules-bt
      ];

      hardware.bluetooth.package = pkgs.bluez5-experimental;
      environment.systemPackages = with pkgs; [
        pulseaudio # pactl
        libopenaptx
        libfreeaptx
        pulseaudio
      ];
      home-manager.sharedModules = [{
        home.persistence."usr/config".directories = [
          ".config/pulse"
          ".config/pipewire"
          ".local/state/wireplumber"
        ];
        home.persistence."usr/config".files = [
          ".config/pavucontrol.ini"
        ];
      }];
    }
    (lib.mkIf config.kdn.headless.enableGUI {
      environment.systemPackages = with pkgs; [
        pavucontrol
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

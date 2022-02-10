{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.hw.pipewire;
in {
  options = {
    nazarewk.hw.pipewire = {
      enable = mkEnableOption "Pipewire setup";

      systemWide = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      useWireplumber = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };
  };

  config = mkIf cfg.enable {
    services.pipewire.systemWide = cfg.systemWide;

    # SOUND - PipeWire
    # see additional pavucontrol package
    security.rtkit.enable = true;
    hardware.pulseaudio.enable = false;
    services.pipewire.enable = true;
    services.pipewire.alsa.enable = true;
    services.pipewire.alsa.support32Bit = true;
    services.pipewire.pulse.enable = true;
    services.pipewire.jack.enable = true;

    services.pipewire.wireplumber.enable = cfg.useWireplumber;
    services.pipewire.media-session.enable = !cfg.useWireplumber;

    sound.mediaKeys.enable = true;
    hardware.pulseaudio.extraModules = [
      pkgs.pulseaudio-modules-bt
    ];


    environment.systemPackages = with pkgs; [
      pavucontrol
    ];
  };
}

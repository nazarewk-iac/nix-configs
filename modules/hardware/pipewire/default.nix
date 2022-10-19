{ lib, pkgs, config, ... }:
with lib;
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

  config = mkIf cfg.enable {
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

    # fixes missing pactl https://github.com/NixOS/nixpkgs/pull/165125
    systemd.user.services.pipewire-pulse.path = [ pkgs.pulseaudio ];
    hardware.bluetooth.package = pkgs.bluez5-experimental;

    environment.systemPackages = with pkgs; [
      pavucontrol
      pulseaudio # pactl
      helvum # A GTK patchbay for pipewire
    ];
  };
}

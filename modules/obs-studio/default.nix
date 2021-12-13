{ lib, pkgs, config, ... }:
{
  config = {
    environment.systemPackages = with pkgs; [
      obs-studio
      obs-studio-plugins.wlrobs
      obs-studio-plugins.obs-gstreamer
    ];
  };
}
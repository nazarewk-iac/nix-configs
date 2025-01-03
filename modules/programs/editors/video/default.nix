{
  lib,
  pkgs,
  config,
  inputs,
  ...
}: let
  cfg = config.kdn.programs.editors.video;
in {
  options.kdn.programs.editors.video.enable = lib.mkEnableOption "Video editing software";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # shotcut # TODO: fails to build jack1 https://github.com/NixOS/nixpkgs/issues/367870
      kdePackages.kdenlive
      handbrake
    ];
  };
}

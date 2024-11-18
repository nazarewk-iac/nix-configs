{
  lib,
  pkgs,
  config,
  inputs,
  ...
}: let
  cfg = config.kdn.programs.gtimelog;
in {
  options.kdn.programs.gtimelog = {
    enable = lib.mkEnableOption "gtimelog setup";
  };

  config = lib.mkIf cfg.enable {
    # doesn't discover gtk?
    environment.systemPackages = with pkgs; [
      kdn.gtimelog
    ];
  };
}

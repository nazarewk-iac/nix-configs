{ lib, pkgs, config, inputs, ... }:
with lib;
let
  cfg = config.kdn.programs.gtimelog;
in
{
  options.kdn.programs.gtimelog = {
    enable = lib.mkEnableOption "gtimelog setup";
  };

  config = mkIf cfg.enable {
    # doesn't discover gtk?
    environment.systemPackages = with pkgs; [
      kdn.gtimelog
    ];
  };
}

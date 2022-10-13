{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.programs.keepass;
in
{
  options.kdn.programs.keepass = {
    enable = mkEnableOption "keepass with plugins";
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [
      (final: prev: {
        keepass = prev.keepass.override {
          plugins = with pkgs; [
            keepass-keeagent
            keepass-keepassrpc
            keepass-keetraytotp
            keepass-charactercopy
            keepass-qrcodeview
          ];
        };
      })
    ];
  };
}

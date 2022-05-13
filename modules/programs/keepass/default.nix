{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.programs.keepass;
in
{
  options.nazarewk.programs.keepass = {
    enable = mkEnableOption "keepass with plugins";
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [
      (self: super: {
        keepass = super.keepass.override {
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

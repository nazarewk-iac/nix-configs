{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.keepass;
in {
  options.kdn.programs.keepass = {
    enable = lib.mkEnableOption "keepass with plugins";
  };

  config = lib.mkIf cfg.enable {
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

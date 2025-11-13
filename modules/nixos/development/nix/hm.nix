{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.nix;
in {
  config = lib.mkIf cfg.enable {
    programs.helix.extraPackages = with pkgs; [
      nil
      nixd
    ];

    programs.helix.languages.language = [
      {
        name = "nix";
        auto-format = true;
        formatter = {
          command = lib.getExe pkgs.kdn.kdn-nix-fmt;
        };
      }
    ];
  };
}

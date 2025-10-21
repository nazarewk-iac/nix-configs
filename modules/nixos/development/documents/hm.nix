{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.development.documents;
in
{
  options.kdn.development.documents = {
    enable = lib.mkEnableOption "documents development";
  };

  config = lib.mkIf cfg.enable {
    programs.helix.extraPackages = with pkgs; [
      marksman
    ];
  };
}

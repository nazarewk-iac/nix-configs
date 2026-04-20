{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.virtualisation.containers.distrobox;
in
{
  options.kdn.virtualisation.containers.distrobox = {
    enable = lib.mkEnableOption "distrobox setup";
  };

  # distrobox is only supported on NixOS
  config = lib.mkIf (cfg.enable && kdnConfig.moduleType == "nixos") (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          distrobox
        ];
      }
    ]
  );
}

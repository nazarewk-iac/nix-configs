{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.virtualisation.vagrant;
in
{
  options.kdn.virtualisation.vagrant = {
    enable = lib.mkEnableOption "Vagrant setup";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.virtualisation.libvirtd.enable = true;
          environment.systemPackages = with pkgs; [
            vagrant
          ];
        }
      ]
    )
  );
}

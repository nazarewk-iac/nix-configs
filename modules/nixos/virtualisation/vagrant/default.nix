{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.virtualisation.vagrant;
in {
  options.kdn.virtualisation.vagrant = {
    enable = lib.mkEnableOption "Vagrant setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.virtualisation.libvirtd.enable = true;
      environment.systemPackages = with pkgs; [
        vagrant
      ];
    }
  ]);
}

{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.terraform;
in
{
  options.kdn.development.terraform = {
    enable = lib.mkEnableOption "Terraform development";
  };

  config = lib.mkIf cfg.enable {
    kdn.packaging.asdf.enable = true;

    home-manager.sharedModules = [
      ./hm.nix
      {
        kdn.development.terraform.enable = true;
      }
    ];
  };
}

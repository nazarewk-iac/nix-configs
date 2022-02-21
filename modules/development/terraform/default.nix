{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.terraform;
in {
  options.nazarewk.development.terraform = {
    enable = mkEnableOption "Terraform development";
  };

  config = mkIf cfg.enable {
    nazarewk.packaging.asdf.enable = true;

    home-manager.sharedModules = [
      ./hm.nix
      {
        nazarewk.development.terraform.enable = true;
      }
    ];
  };
}
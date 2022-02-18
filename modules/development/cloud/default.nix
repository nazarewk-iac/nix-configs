{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.cloud;
in {
  options.nazarewk.development.cloud = {
    enable = mkEnableOption "cloud development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # dev software
      nodejs
      yarn

      # AWS
      awscli2
      eksctl

      # Argo
      argocd
    ];
  };
}
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

      (pkgs.writeShellApplication {
        name = "aws-list-all-parameters";
        runtimeInputs = with pkgs; [ awscli2 coreutils jq ];
        text = builtins.readFile ./bin/aws-list-all-parameters.sh;
      })
    ];
  };
}
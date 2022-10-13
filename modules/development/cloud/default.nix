{ lib, pkgs, config, system, ... }:
with lib;
let
  cfg = config.kdn.development.cloud;
in
{
  options.kdn.development.cloud = {
    enable = mkEnableOption "cloud development";
  };

  config = mkIf cfg.enable {
    kdn.development.nodejs.enable = true;
    kdn.development.lua.enable = true;

    environment.systemPackages = with pkgs; [
      # AWS
      awscli2
      eksctl

      # Argo
      argocd
      vault

      (pkgs.writeShellApplication {
        name = "aws-list-all-parameters";
        runtimeInputs = with pkgs; [ awscli2 coreutils jq ];
        text = builtins.readFile ./bin/aws-list-all-parameters.sh;
      })
    ];
  };
}

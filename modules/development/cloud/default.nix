{ lib, pkgs, config, system, ... }:
with lib;
let
  cfg = config.kdn.development.cloud;
in
{
  options.kdn.development.cloud = {
    enable = lib.mkEnableOption "cloud development";
  };

  config = lib.mkIf cfg.enable {
    kdn.development.nodejs.enable = true;
    kdn.development.lua.enable = true;
    kdn.programs.aws-vault.enable = true;

    environment.systemPackages = with pkgs; [
      # AWS
      awscli2
      ssm-session-manager-plugin
      eksctl

      redis

      # Argo
      argo # workflows
      argocd # CD
      vault

      (pkgs.writeShellApplication {
        name = "aws-list-all-parameters";
        runtimeInputs = with pkgs; [ awscli2 coreutils jq ];
        text = builtins.readFile ./bin/aws-list-all-parameters.sh;
      })
      (pkgs.writeShellApplication {
        name = "argo-eks-token";
        runtimeInputs = with pkgs; [ awscli2 jq ];
        text = builtins.readFile ./bin/argo-eks-token.sh;
      })
    ];
  };
}

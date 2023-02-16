{ lib, pkgs, config, system, ... }:
with lib;
let
  cfg = config.kdn.development.cloud;
in
{
  options.kdn.development.cloud = {
    enable = lib.mkEnableOption "cloud development";
  };

  config = mkIf cfg.enable {
    # TODO: error: Package ‘v8-8.8.278.14’ in /nix/store/yxcvhxxlq7q6284hmwzvnzcg1g5aph47-source/pkgs/development/libraries/v8/8_x.nix:166 is marked as broken, refusing to evaluate.
    kdn.development.nodejs.enable = true;
    kdn.development.lua.enable = true;
    kdn.programs.aws-vault.enable = true;

    environment.systemPackages = with pkgs; [
      # AWS
      awscli2
      ssm-session-manager-plugin
      eksctl

      # Argo
      argo # workflowg
      argocd # CD
      vault

      (pkgs.writeShellApplication {
        name = "aws-list-all-parameters";
        runtimeInputs = with pkgs; [ awscli2 coreutils jq ];
        text = builtins.readFile ./bin/aws-list-all-parameters.sh;
      })
    ];
  };
}

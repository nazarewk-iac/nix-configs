{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.cloud.aws;
in {
  options.kdn.development.cloud.aws = {
    enable = lib.mkEnableOption "AWS cloud development";
  };

  config = lib.mkIf cfg.enable {
    kdn.disks.persist."usr/data".directories = [".aws"];
    kdn.env.packages = with pkgs; [
      # AWS
      awscli2
      (lib.mkIf (let p = pkgs.stdenv.hostPlatform; in p.isx86_64 && (p.isLinux || p.isDarwin)) amazon-ecs-cli)
      ssm-session-manager-plugin
      eksctl

      (pkgs.writeShellApplication {
        name = "aws-list-all-parameters";
        runtimeInputs = with pkgs; [
          awscli2
          coreutils
          jq
        ];
        text = builtins.readFile ./bin/aws-list-all-parameters.sh;
      })
      (pkgs.writeShellApplication {
        name = "argo-eks-token";
        runtimeInputs = with pkgs; [
          awscli2
          jq
        ];
        text = builtins.readFile ./bin/argo-eks-token.sh;
      })
    ];
  };
}

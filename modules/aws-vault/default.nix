{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.programs.aws-vault;
in
{
  options.programs.aws-vault = {
    enable = mkEnableOption "aws-vault + aliases";
  };

  config = mkIf cfg.enable {
    programs.zsh.interactiveShellInit = ''
      eval "$(${pkgs.aws-vault}/bin/aws-vault --completion-script-zsh)"
    '';
    programs.bash.interactiveShellInit = ''
      eval "$(${pkgs.aws-vault}/bin/aws-vault --completion-script-bash)"
    '';

    environment.sessionVariables = {
      AWS_VAULT_PROMPT = "ykman";
      AWS_ASSUME_ROLE_TTL = "8h";
      AWS_VAULT_BACKEND = "pass";
      AWS_VAULT_PASS_PREFIX = "aws-vault";
    };

    environment.systemPackages = with pkgs; [
      (writeShellApplication {
        name = "aws-shell";
        runtimeInputs = [ aws-vault ];
        text = ''
          aws-vault exec -n "@"
        '';
      })
      (writeShellApplication {
        name = "aws-login";
        runtimeInputs = [ aws-vault ];
        text = ''
          aws-vault login "@"
        '';
      })
    ];
  };
}
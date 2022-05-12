{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.programs.aws-vault;

  aws-vault = pkgs.writeShellApplication {
    name = "aws-vault";
    runtimeInputs = [ cfg.package ];
    text = ''
      export ${concatStringsSep " \\\n  " cfg.defaultEnv}
      exec aws-vault "$@"
    '';
  };

  mkScript = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = [ aws-vault ];
  };

  # escapeShellArg = arg: "'${replaceStrings ["'"] ["'\\''"] (toString arg)}'";
  escapeDefault = arg: ''"${replaceStrings [''"''] [''\"''] (toString arg)}"'';
in
{
  options.nazarewk.programs.aws-vault = {
    enable = mkEnableOption "aws-vault + aliases";

    package = mkOption {
      type = types.package;
      default = pkgs.aws-vault;
      defaultText = literalExpression "pkgs.aws-vault";
    };

    defaultEnv = mkOption {
      default = {
        AWS_VAULT_PROMPT = "ykman";
        AWS_ASSUME_ROLE_TTL = "8h";
        AWS_VAULT_BACKEND = "pass";
        AWS_VAULT_PASS_PREFIX = "aws-vault";
      };
      description = ''
        A set of default environment variables to be used in aws-vault invocations
      '';
      type = with types; attrsOf str;
      apply = input: (mapAttrsToList (n: v: "${n}=\"\${${n}:-${escapeDefault v}}\"") input);
    };
  };

  config = mkIf cfg.enable {
    programs.zsh.interactiveShellInit = ''
      eval "$(${aws-vault}/bin/aws-vault --completion-script-zsh)"
    '';
    programs.bash.interactiveShellInit = ''
      eval "$(${aws-vault}/bin/aws-vault --completion-script-bash)"
    '';

    environment.systemPackages = [
      aws-vault
      (mkScript "aws-shell" ''aws-vault exec -n "$@"'')
      (mkScript "aws-login" ''aws-vault login "$@"'')
      (mkScript "aws-profiles" ''grep '\[profile' "''${AWS_CONFIG_FILE:-"$HOME/.aws/config"}" | sed -r 's/^\[profile (.*)\]$/\1/' | sort'')
    ];
  };
}

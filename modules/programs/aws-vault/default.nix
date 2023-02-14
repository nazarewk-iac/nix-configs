{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.programs.aws-vault;

  aws-vault-wrapper = pkgs.writeShellApplication {
    name = "aws-vault";
    runtimeInputs = [ cfg.package ];
    text = ''
      export ${concatStringsSep " \\\n  " cfg.defaultEnv}
      if [[ -n "''${AWS_VAULT_CONFIG_FILE:-}" ]] ; then
        AWS_CONFIG_FILE="$AWS_VAULT_CONFIG_FILE"
      elif [[ "''${AWS_CONFIG_FILE:-}" != *.vault ]] ; then
        AWS_CONFIG_FILE="''${AWS_CONFIG_FILE:-"$HOME/.aws/config"}"
        AWS_CONFIG_FILE="$AWS_CONFIG_FILE.vault"
      fi
      export AWS_CONFIG_FILE
      exec aws-vault "$@"
    '';
  };

  # symlinks the rest to provide completion scripts
  aws-vault = pkgs.symlinkJoin {
    name = "aws-vault";
    paths = [ aws-vault-wrapper cfg.package ];
    postBuild = "echo links added";
  };

  mkScript = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = [ aws-vault ];
  };
in
{
  options.kdn.programs.aws-vault = {
    enable = lib.mkEnableOption "aws-vault + aliases";

    package = mkOption {
      type = types.package;
      default = pkgs.aws-vault;
      defaultText = literalExpression "pkgs.aws-vault";
    };

    defaultEnv = mkOption {
      default = {
        AWS_VAULT_PROMPT = "terminal"; # ykman conflicts with GPG decryption
        AWS_SESSION_TOKEN_TTL = "12h";
        AWS_MIN_TTL = "2h";
        AWS_VAULT_BACKEND = "pass";
        AWS_VAULT_PASS_PREFIX = "aws-vault";
      };
      description = ''
        A set of default environment variables to be used in aws-vault invocations
      '';
      type = with types; attrsOf str;
      apply = lib.kdn.shell.makeShellDefaultAssignments;
    };
  };

  config = mkIf cfg.enable {
    environment.shellAliases = {
      "av" = "aws-vault";
      "avr" = "aws-vault rotate -n";
    };

    environment.systemPackages = [
      aws-vault
      (mkScript "avl" (builtins.readFile ./avl.sh))
      (mkScript "aws-profiles" ''grep '\[profile' "''${AWS_CONFIG_FILE:-"$HOME/.aws/config"}" | sed -r 's/^\[profile (.*)\]$/\1/' | sort'')
    ];
  };
}

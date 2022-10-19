{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.work.development;
  relDir = "${cfg.baseDir}";
  absDir = "${config.home.homeDirectory}/${relDir}";
  shellDir = "$HOME/${relDir}";
in
{
  options.kdn.work.development = {
    enable = lib.mkEnableOption "development utilities";

    prefix = mkOption {
      default = "w";
      description = "The prefix work tooling will take";
    };

    domains = mkOption {
      type = types.listOf types.str;
    };

    bastionUsername = mkOption {
      default = config.home.username;
      description = "SSH Username to use for bastion host";
    };

    baseDir = mkOption {
      description = "Base development directory";
    };

    git.remoteShellPattern = mkOption {
      # "git@github.com:<org>/$repo.git"
    };
  };

  config = mkIf cfg.enable {
    programs.ssh.extraConfig = ''
      Host ${cfg.domains}
          User ${cfg.bastionUsername}
    '';
    programs.bash.initExtra = config.programs.zsh.initExtra;
    programs.zsh.initExtra = ''
      export WORK_DIR="${shellDir}"

      ${cfg.prefix}cd() {
        cd "$WORK_DIR/''${1:-""}"
      }
    '';

    home.file."${relDir}/.envrc" = {
      text = ''
        source_env .envrc.secret
        env_vars_required WORK_BASTION_CIDR WORK_BASTION_HOST PASSWORD_STORE_DIR

        source_env_if_exists .envrc.dynamic

        export AWS_CONFIG_FILE="$PWD/.aws/config"
        export AWS_SHARED_CREDENTIALS_FILE="$PWD/.aws/credentials"
        export KUBECONFIG="$PWD/.kube/config"

        # These are currently not configurable, pending https://github.com/benkehoe/aws-sso-util/pull/63
        export AWS_SSO_UTIL_SSO_TOKEN_DIR="$PWD/.aws/sso/cache"
        export AWS_SSO_UTIL_CREDENTIALS_CACHE_DIR="$PWD/.aws/cli/cache"
      '';

      onChange = ''${pkgs.sudo}/bin/sudo -u ${config.home.username} ${pkgs.direnv}/bin/direnv allow "$WORK_DIR/.envrc"'';
    };

    home.packages = with pkgs; [
      ansible
      circleci-cli

      (pkgs.writeShellApplication {
        name = "${cfg.prefix}gh-clone";
        runtimeInputs = with pkgs; [ git ];
        text = ''
          for repo in "$@"; do
            git clone "${cfg.git.remoteShellPattern}" "$WORK_DIR/$repo"
          done
        '';
      })

      (pkgs.writeShellApplication {
        name = "${cfg.prefix}vpn";
        runtimeInputs = with pkgs; [ sshuttle ];
        text = ''
          host="''${1:-"''${WORK_BASTION_HOST}"}"
          cidr="''${2:-"''${WORK_BASTION_CIDR}"}"
          username="${cfg.bastionUsername}"
          set -x
          sshuttle -r "$username@$host" "$cidr" --no-latency-control "''${@:3}"
        '';
      })
    ];
  };
}

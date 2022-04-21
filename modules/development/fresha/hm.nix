{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.fresha.development;
  relDir = "${cfg.baseDir}";
  absDir = "${config.home.homeDirectory}/${relDir}";
  shellDir = "$HOME/${relDir}";
in {
  options.fresha.development = {
    enable = mkEnableOption "Fresha development utilities";

    prefix = mkOption {
      default = "f";
      description = "The prefix fresha tooling will take";
    };

    bastionUsername = mkOption {
      default = config.home.username;
      description = "SSH Username to use for bastion host";
    };

    baseDir = mkOption {
      default = "dev/github.com/surgeventures";
      description = "Base development directory for Fresha";
    };

    git.remoteShellPattern = mkOption {
      default = "git@github.com:surgeventures/$repo.git";
    };
  };

  config = mkIf cfg.enable {
    programs.ssh.extraConfig = ''
      Host *.fresha.io *.shedul.io
          User ${cfg.bastionUsername}
    '';
    programs.bash.initExtra = config.programs.zsh.initExtra;
    programs.zsh.initExtra = ''
      export FRESHA_DIR="${shellDir}"

      ${cfg.prefix}cd() {
        cd "$FRESHA_DIR/''${1:-""}"
      }
    '';

    home.file."${relDir}/.envrc" = {
      text = ''
      source_env .envrc.secret
      env_vars_required FRESHA_BASTION_CIDR FRESHA_BASTION_HOST PASSWORD_STORE_DIR

      source_env_if_exists .envrc.dynamic

      export AWS_CONFIG_FILE="$PWD/.aws/config"
      export AWS_SHARED_CREDENTIALS_FILE="$PWD/.aws/credentials"
      export KUBECONFIG="$PWD/.kube/config"

      # These are currently not configurable, pending https://github.com/benkehoe/aws-sso-util/pull/63
      export AWS_SSO_UTIL_SSO_TOKEN_DIR="$PWD/.aws/sso/cache"
      export AWS_SSO_UTIL_CREDENTIALS_CACHE_DIR="$PWD/.aws/cli/cache"
      '';

      onChange = ''${pkgs.sudo}/bin/sudo -u ${config.home.username} ${pkgs.direnv}/bin/direnv allow "$FRESHA_DIR/.envrc"'';
    };

    home.packages = with pkgs; [
      ansible

      (pkgs.writeShellApplication {
        name = "${cfg.prefix}gh-clone";
        runtimeInputs = with pkgs; [ git ];
        text = ''
          for repo in "$@"; do
            git clone "${cfg.git.remoteShellPattern}" "$FRESHA_DIR/$repo"
          done
        '';
      })

      (pkgs.writeShellApplication {
        name = "${cfg.prefix}vpn";
        runtimeInputs = with pkgs; [ sshuttle ];
        text = ''
          host="''${1:-"''${FRESHA_BASTION_HOST}"}"
          cidr="''${2:-"''${FRESHA_BASTION_CIDR}"}"
          username="${cfg.bastionUsername}"
          set -x
          sshuttle -r "$username@$host" "$cidr" --no-latency-control "''${@:3}"
        '';
      })
    ];
  };
}
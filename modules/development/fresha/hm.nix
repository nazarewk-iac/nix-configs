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
        cd "$FRESHA_DIR''${1:-""}"
      }
    '';

    home.file."${relDir}/.envrc" = {
      source = ./files/.envrc;
      onChange = ''${pkgs.direnv}/bin/direnv allow "$FRESHA_DIR/.envrc"'';
    };

    home.packages = [
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
          bastion="''${1:-"''${FRESHA_BASTION_HOST}"}"
          cidr="''${2:-"''${FRESHA_BASTION_CIDR}"}"
          username="${cfg.bastionUsername}"
          set -x
          sshuttle -r "$username@$bastion" "$cidr" --no-latency-control "''${@:3}"
        '';
      })

      (pkgs.writeShellApplication {
        name = "${cfg.prefix}eksconfig";
        runtimeInputs = with pkgs; [ awscli2 kubectl ];
        text = ''
          cluster_name="$1"
          profile="''${2:-"$AWS_PROFILE"}"
          set -x
          aws eks update-kubeconfig --profile="$profile" --name="$cluster_name" --alias="$cluster_name"
          # set ARN-based context
          # shellcheck disable=SC2046
          kubectl config set-context $(kubectl config get-contexts "$cluster_name" | tail -n1 | awk '{ print $3 " --cluster=" $3 " --user=" $4 }')
        '';
      })
    ];
  };
}
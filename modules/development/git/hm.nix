{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.git;
  relDir = "${cfg.baseDir}";
  absDir = "${config.home.homeDirectory}/${relDir}";
  shellDir = "$HOME/${relDir}";

  gDir = lib.kdn.shell.writeShellScript pkgs ./bin/g-dir.sh {
    prefix = ''
      shellDir="${shellDir}"
    '';
  };
  gGet = lib.kdn.shell.writeShellScript pkgs ./bin/g-get.sh {
    runtimeInputs = with pkgs; [ git gDir gRemote ];
  };
  gRemote = lib.kdn.shell.writeShellScript pkgs ./bin/g-remote.sh { };
  ghRepos = lib.kdn.shell.writeShellScript pkgs ./bin/gh-repos.sh {
    runtimeInputs = with pkgs; [ gh jq ];
  };
  ghGetAll = lib.kdn.shell.writeShellScript pkgs ./bin/gh-get-all.sh {
    runtimeInputs = with pkgs; [ ghRepos ];
  };

in
{
  options.kdn.development.git = {
    enable = lib.mkEnableOption "Git development utilities";

    baseDir = mkOption {
      default = "dev";
      description = "Base git checkout directory";
    };

    remoteShellPattern = mkOption {
      default = "https://github.com/$org/$repo.git";
    };
  };
  config = mkIf cfg.enable {
    programs.bash.initExtra = config.programs.zsh.initExtra;
    programs.zsh.initExtra = ''
      gh-cd() {
        cd "$(${gDir}/bin/g-dir $1)"
      }
    '';

    home.packages = with pkgs; [
      gDir
      gRemote
      gGet

      ghGetAll
      ghRepos

      hub
      gh
    ];
  };
}

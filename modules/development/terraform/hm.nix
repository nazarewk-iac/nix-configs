{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.terraform;
in {
  options.nazarewk.development.terraform = {
    enable = mkEnableOption "Terraform development";
  };

  config = mkIf cfg.enable {
    programs.git.ignores = [ (builtins.readFile ./.gitignore) ];

    home.sessionVariables = {
      TF_CLI_CONFIG_FILE = "${config.xdg.configHome}/terraform/.terraformrc";
    };

    xdg.configFile."terraform/.terraformrc".text = ''
      plugin_cache_dir = "${config.xdg.cacheHome}/terraform/plugin-cache"
    '';
  };
}
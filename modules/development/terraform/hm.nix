{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.terraform;
in
{
  options.kdn.development.terraform = {
    enable = lib.mkEnableOption "Terraform development";
  };

  config = mkIf cfg.enable {
    programs.git.ignores = [ (builtins.readFile ./.gitignore) ];

    home.sessionVariables = {
      TF_CLI_CONFIG_FILE = "${config.xdg.configHome}/terraform/.terraformrc";
    };

    xdg.configFile."terraform/.terraformrc".text = ''
      plugin_cache_dir = "${config.xdg.cacheHome}/terraform/plugin-cache"
    '';

    home.file.".tool-versions".source = ./.tool-versions;

    programs.bash.initExtra = config.programs.zsh.initExtra;
    programs.zsh.initExtra = ''
      mkdir -p "${config.xdg.cacheHome}/terraform/plugin-cache"
    '';

    home.packages = with pkgs; [
      (pkgs.writeShellApplication {
        name = "tf-fmt";
        runtimeInputs = with pkgs; [ pkgs.gnugrep pkgs.gnused pkgs.coreutils pkgs.findutils ];
        text = ''
          since_revision="$1"
          cd "$(git rev-parse --show-toplevel)"

          if command -v terraform ; then
            git diff --name-only "$since_revision" | grep -E '.(tf|tfvars)$' | sed 's#/[^/]*$##g' | sort | uniq \
              | xargs -n1 -r terraform fmt
          else
            echo 'terraform executable is missing, skipping...'
          fi

          if command -v terragrunt ; then
            git diff --name-only "$since_revision" | grep -E '.(hcl)$' \
              | xargs -n1 -r terragrunt hclfmt --terragrunt-hclfmt-file
          else
            echo 'terragrunt executable is missing, skipping...'
          fi
        '';
      })
    ];
  };
}

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

    home.shellAliases =
      let
        mkAliases = cmd: short: {
          "${short}" = cmd;
          "${short}g" = "${cmd} get";
          "${short}i" = "${cmd} init";
          "${short}ir" = "${cmd} init --reconfigure";
          "${short}im" = "${cmd} import";
          "${short}iu" = "${cmd} init --upgrade";
          "${short}p" = "${cmd} plan";
          "${short}a" = "${cmd} apply";
          "${short}aa" = "${cmd} apply --auto-approve";
          "${short}u" = "${cmd} force-unlock --force";
        };
      in
      (
        mkAliases "terraform" "tf"
      ) // {
        "tff" = "terraform fmt --recursive";
      } // (
        mkAliases "terragrunt" "tg"
      ) // {
        "tgf" = "terragrunt hclfmt";
        "tgr" = "terragrunt render-json --terragrunt-json-out=/dev/stdout | jq";
        "tgrm" = "terragrunt render-json --with-metadata --terragrunt-json-out=/dev/stdout | jq";
      };

    home.packages = with pkgs; [
      terraform-ls # see https://github.com/hashicorp/terraform-ls/blob/main/docs/USAGE.md
      (pkgs.writeShellApplication {
        name = "tf-fmt";
        runtimeInputs = with pkgs; [ gnugrep gnused coreutils findutils moreutils gojq ];
        text = builtins.readFile ./tf-fmt.sh;
      })
    ];
  };
}

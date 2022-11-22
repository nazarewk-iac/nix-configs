{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.terraform;
in
{
  options.kdn.development.terraform = {
    enable = lib.mkEnableOption "Terraform development";
  };

  config = lib.mkIf cfg.enable {
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
        mkAliases = cmd: short: extra: {
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
          "${short}o" = "${cmd} output";
          "${short}oj" = "${cmd} output --json";
        } // (builtins.mapAttrs (short: entry: "${cmd} ${entry}") extra);

      in
      (mkAliases "terraform" "tf" {
        "tff" = "terraform fmt --recursive";
      }) // (mkAliases "TERRAGRUNT_FETCH_DEPENDENCY_OUTPUT_FROM_STATE=true terragrunt" "tg" {
        "tgf" = "hclfmt";
        "tgs" = "render-json --terragrunt-json-out=/dev/stdout | jq";
        "tgsm" = "render-json --with-metadata --terragrunt-json-out=/dev/stdout | jq";
        "tgr" = "run-all";
        "tgrc" = "run-all --terragrunt-ignore-external-dependencies";
      });

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

{ lib, pkgs, config, ... }:
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
        platformsArgs = builtins.concatStringsSep " " (map (p: "--platform=${p}") [
          # see https://developer.hashicorp.com/terraform/language/files/dependency-lock
          # see https://gist.github.com/lizkes/975ab2d1b5f9d5fdee5d3fa665bcfde6#file-go-os-arch-md
          "darwin_arm64"
          "darwin_arm64"
          "linux_amd64"
          "linux_arm64"
        ]);
        mkAliases = cmd: short: extra: {
          "${short}" = cmd;
          "${short}a" = "${cmd} apply";
          "${short}aa" = "${cmd} apply --auto-approve";
          "${short}g" = "${cmd} get";
          "${short}i" = "${cmd} init";
          "${short}im" = "${cmd} import";
          "${short}ir" = "${cmd} init --reconfigure";
          "${short}iu" = "${cmd} init --upgrade";
          "${short}l" = "${cmd} providers lock ${platformsArgs}";
          "${short}o" = "${cmd} output";
          "${short}oj" = "${cmd} output --json";
          "${short}p" = "${cmd} plan";
          "${short}u" = "${cmd} force-unlock --force";
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
      terranix
      terraformer
      terraform-ls # see https://github.com/hashicorp/terraform-ls/blob/main/docs/USAGE.md
      (pkgs.writeShellApplication {
        name = "tf-fmt";
        runtimeInputs = with pkgs; [ gnugrep gnused coreutils findutils moreutils gojq ];
        text = builtins.readFile ./tf-fmt.sh;
      })
    ];
  };
}

# The `development/terraform` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It gives one user OpenTofu, Terraform, `terranix` and the `tf-fmt` script. It also points the
# plugin cache and the CLI configuration file at the XDG directories, adds the Terraform Git
# ignores, and declares about forty shell aliases for OpenTofu and Terragrunt.
#
# It is a Home Manager opinion only. The old NixOS half does two things and neither one survives:
# it forwards the flag to Home Manager, and it turns another area on.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` and `kdn.env.variables` go.** The target writes `home.packages` through
#    ../common/filter-packages.nix, and `home.sessionVariables` directly. Design B.
# 3. **The old `kdn.packaging.asdf.enable` write goes.** A host states that aspect itself. The old
#    line is `lib.mkDefault true`, so a machine that wants it names `packaging` in its own list.
# 4. **Two data files move next to this file, with no leading dot.** `./dev-terraform/gitignore`
#    and `./dev-terraform/tool-versions` are copies. A file named `.gitignore` inside the aspect
#    tree would act as a real ignore file for this repository, so the copy drops the dot. The
#    content is byte for byte the same, and `home.file` still writes the target name
#    `.tool-versions`.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.dev-terraform.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      programs.git.ignores = [ (builtins.readFile ./dev-terraform/gitignore) ];

      home.sessionVariables = {
        TF_CLI_CONFIG_FILE = "${config.xdg.configHome}/tofu/.tofurc";
        TERRAGRUNT_TFPATH = "tofu";
      };

      xdg.configFile."tofu/.tofurc".text = ''
        plugin_cache_dir = "${config.xdg.cacheHome}/tofu/plugin-cache"
      '';
      home.file.".tool-versions".source = ./dev-terraform/tool-versions;

      programs.bash.initExtra = config.programs.zsh.initContent;
      programs.zsh.initContent = ''
        mkdir -p "${config.xdg.cacheHome}/tofu/plugin-cache"
      '';

      home.shellAliases =
        let
          platformsArgs = builtins.concatStringsSep " " (
            # see https://developer.hashicorp.com/terraform/language/files/dependency-lock
            # see https://gist.github.com/lizkes/975ab2d1b5f9d5fdee5d3fa665bcfde6#file-go-os-arch-md
            map (p: "--platform=${p}") [
              "darwin_arm64"
              "darwin_arm64"
              "linux_amd64"
              "linux_arm64"
            ]
          );
          mkAliases =
            cmd: short: extra:
            {
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
              "${short}v" = "${cmd} validate";
            }
            // (builtins.mapAttrs (short: entry: "${cmd} ${entry}") extra);
        in
        (mkAliases "tofu" "tf" { "tff" = "tofu fmt --recursive"; })
        // (mkAliases "TERRAGRUNT_FETCH_DEPENDENCY_OUTPUT_FROM_STATE=true terragrunt" "tg" {
          "tgf" = "hclfmt";
          "tgs" = "render-json --terragrunt-json-out=/dev/stdout | jq";
          "tgsm" = "render-json --with-metadata --terragrunt-json-out=/dev/stdout | jq";
          "tgr" = "run-all";
          "tgrc" = "run-all --terragrunt-ignore-external-dependencies";
        });

      home.packages = filterPackages (
        with pkgs;
        [
          opentofu
          terraform
          # terragrunt # TODO: enable when https://nixpk.gs/pr-tracker.html?pr=389836
          terranix
          (pkgs.writeShellApplication {
            name = "tf-fmt";
            runtimeInputs = with pkgs; [
              gnugrep
              gnused
              coreutils
              findutils
              moreutils
              gojq
            ];
            text = builtins.readFile ./dev-terraform/tf-fmt.sh;
          })
        ]
      );

      # TODO: replace with https://github.com/gamunu/vscode-opentofu
      programs.helix.extraPackages = with pkgs; [ terraform-ls ];
    };
}

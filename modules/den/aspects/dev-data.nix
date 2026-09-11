# The `development/data` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs the data tool set: `jq`, `yq-go`, `miller`, `cue`, `conftest`, the HCL converters and
# more. On Home Manager it also adds a language server per data format to Helix, and it teaches
# Helix the `jq` language.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` goes.** Each target writes the native package option of its own class,
#    through ../common/filter-packages.nix. Design B.
# 3. **`pkgs.kdn.data-converters` becomes a plain `callPackage`.** The old module reads the `kdn`
#    package set, so a consumer must add this repository's overlay first. A relative path needs no
#    overlay.
# 4. **The forward to Home Manager goes.** den needs no forward: a consumer names the class it
#    wants.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module below takes `lib` and `pkgs` only.
{ ... }:
let
  packages =
    pkgs:
    (with pkgs; [
      miller
      yq-go
      jq
      yj

      gojq
      ijq # an interactive `jq`
      jc # it converts the output of a command to JSON
      gron # JSON to and from a list of path-value assignments
      (pkgs.writeShellApplication {
        name = "ungron";
        text = ''${gron}/bin/gron --ungron "$@"'';
      })

      cue
      conftest

      gnused

      # It converts HCL to and from JSON.
      python3Packages.bc-python-hcl2
      hcl2json
      sqlite
    ])
    ++ [ (pkgs.callPackage ../../../packages/data-converters { }) ];

  filtered = lib: pkgs: import ../common/filter-packages.nix { inherit lib; } (packages pkgs);

  systemTarget =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = filtered lib pkgs;
    };
in
{
  kdn.dev-data.nixos = systemTarget;
  kdn.dev-data.darwin = systemTarget;

  kdn.dev-data.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = filtered lib pkgs;

      programs.helix.extraPackages = with pkgs; [
        cuelsp
        jsonnet-language-server
        vscode-json-languageserver
        taplo # TOML
        yaml-language-server
      ];

      programs.helix.languages.language-server.jq-lsp.command = lib.getExe pkgs.jq-lsp;
      programs.helix.languages.language = [
        {
          name = "jq";
          language-servers = [ "jq-lsp" ];
          roots = [ ];
          file-types = [
            "jq"
            "jql"
          ];
          scope = "source.jq";
          comment-token = "#";
          indent = {
            tab-width = 2;
            unit = "  ";
          };
        }
      ];
    };
}

{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.data;
in
{
  options.kdn.development.data = {
    enable = lib.mkEnableOption "tools for working with data";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        programs.helix.extraPackages = with pkgs; [
          cuelsp
          jsonnet-language-server
          vscode-json-languageserver
          taplo # toml
          yaml-language-server
        ];
        programs.helix.languages = {
          language-server.jq-lsp = {
            command = lib.getExe pkgs.jq-lsp;
          };
          language = [
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
    ))
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { kdn.development.data.enable = true; } ];
        environment.systemPackages = with pkgs; [
          miller
          yq-go
          jq
          yj

          pkgs.kdn.data-converters

          gojq
          jiq # interactive JQ
          jc # convert commands output to JSON
          gron # JSON to/from list of path-value assignments
          (pkgs.writeShellApplication {
            name = "ungron";
            text = ''${gron}/bin/gron --ungron "$@"'';
          })

          cue
          conftest

          gnused

          # Convert HCL <-> JSON
          python3Packages.bc-python-hcl2
          hcl2json
          sqlite
        ];
      }
    ))
  ];
}

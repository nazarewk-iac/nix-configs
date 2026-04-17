{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.development.data;
in {
  options.kdn.development.data = {
    enable = lib.mkEnableOption "tools for working with data";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [{kdn.development.data.enable = true;}];
    })

    {
      kdn.env.packages = with pkgs; [
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
    (kdnConfig.util.ifHM {
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
            language-servers = ["jq-lsp"];
            roots = [];
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
    })
  ]);
}

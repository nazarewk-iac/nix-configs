{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.data;
in {
  options.kdn.development.data = {
    enable = lib.mkEnableOption "tools for working with data";
  };

  config = lib.mkIf cfg.enable {
    programs.helix.extraPackages = with pkgs; [
      cuelsp
      jsonnet-language-server
      nodePackages.vscode-json-languageserver
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
  };
}

{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.kdn.mcp.basic-memory;
  bmp = pkgs.kdn.basic-memory.mkWrapper {
    name = "public";
    aliases = [ "bmp" ];
  };
  bms = pkgs.kdn.basic-memory.mkWrapper {
    name = "sensitive";
    aliases = [ "bms" ];
  };
in
{
  options.kdn.mcp.basic-memory = {
    enable = lib.mkEnableOption "basic-memory knowledge base MCP backends";
  };

  config = lib.mkIf cfg.enable {
    packages = [
      bmp
      bms
    ];

    kdn.mcp.extraBackends = {
      memory-public = {
        command = "${bmp}/bin/basic-memory-public mcp";
        description = "basic-memory public knowledge base (open-source tooling, public knowledge)";
      };
      memory-sensitive = {
        command = "${bms}/bin/basic-memory-sensitive mcp";
        description = "basic-memory sensitive knowledge base (private, company-specific)";
      };
    };

    files = lib.mkIf (!config.kdn.isSourceRepo) {
      ".claude/rules/basic-memory.md".source = "${inputs.nix-configs}/.agents/rules/basic-memory.md";
    };
  };
}

# mcpsnoop slot — wraps mcp-gateway with a transparent JSON-RPC inspector.
#
# Appends a commandOverlay that prepends `mcpsnoop --` in front of whatever
# command the mcp slot has built so far.  Open a second terminal and run
# `mcpsnoop` to see the live TUI.  See docs/mcpsnoop.md for usage.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.kdn.mcp.snoop;
in
{
  options.kdn.mcp.snoop = {
    # A slot is side-effect free by default — see .agents/rules/nix-conventions.md. A consumer that
    # wants the inspector sets this option, as devenv.nix of this repository does.
    enable = lib.mkEnableOption "mcpsnoop transparent MCP traffic inspector";
  };

  config = lib.mkIf (config.kdn.mcp.enable && cfg.enable) {
    kdn.mcp.commandOverlays = [
      (
        prevCmd:
        toString (
          pkgs.writeShellScript "mcp-gateway-snoop-wrapper" ''
            exec ${lib.getExe pkgs.kdn.mcpsnoop} -- ${prevCmd}
          ''
        )
      )
    ];

    devenv.packages = [ pkgs.kdn.mcpsnoop ];
  };
}

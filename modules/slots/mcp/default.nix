# MCP gateway slot module.
#
# Bridges mcp-servers-nix program declarations into mcp-gateway backends,
# then registers only the gateway (via --stdio) with claude.code.mcpServers.
# This keeps the LLM's tool surface small (~14 meta-tools) regardless of how
# many MCP servers are configured.
#
# The gateway config is symlinked to .devenv/mcp-gateway.yaml on enterShell
# so that .mcp.json never needs updating between builds.
#
# Requires devenv.yaml input:
#   mcp-servers-nix:
#     url: github:natsukium/mcp-servers-nix
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  cfg = config.kdn.mcp;
  mcp-servers-nix = inputs.mcp-servers-nix or null;

  # Re-use mcp-servers-nix's evalModule to resolve declared programs into
  # a servers attrset: { name = { command, args, env, type, ... }; }
  evaluated =
    if mcp-servers-nix != null then
      let
        mcp-lib = import "${mcp-servers-nix}/lib";
      in
      mcp-lib.evalModule pkgs {
        inherit (cfg) programs;
        settings = { };
        flavor = "claude-code";
      }
    else
      { config.settings.servers = { }; };

  servers = evaluated.config.settings.servers or { };

  # Translate a mcp-servers-nix server entry to a mcp-gateway backend stanza.
  toBackend =
    name: server:
    let
      isHttp = (server.type or "stdio") == "http" || (server.type or "stdio") == "sse";
      cmdStr = lib.concatStringsSep " " (
        [ server.command ] ++ map (a: lib.escapeShellArg (toString a)) (server.args or [ ])
      );
    in
    lib.filterAttrs (_: v: v != null && v != { }) (
      {
        description = name;
      }
      // (if isHttp then { http_url = server.url; } else { command = cmdStr; })
      // lib.optionalAttrs (server ? env && server.env != { }) {
        env = lib.mapAttrs (_: toString) server.env;
      }
      // lib.optionalAttrs (server ? headers && server.headers != { }) {
        inherit (server) headers;
      }
    );

  allBackends = (lib.mapAttrs toBackend servers) // cfg.extraBackends;

  gatewayConfig = (pkgs.formats.yaml { }).generate "mcp-gateway.yaml" {
    server = {
      host = cfg.host;
      port = cfg.port;
    };
    meta_mcp = {
      enabled = true;
      cache_tools = true;
      cache_ttl = "300s";
    };
    backends = allBackends;
  };

  # Stable symlink within the project so .mcp.json never changes between builds.
  # enterShell updates the symlink; the wrapper script expands DEVENV_ROOT at runtime.
  stableConfigLink = ".devenv/mcp-gateway.yaml";

  gatewayWrapper = pkgs.writeShellScript "mcp-gateway-wrapper" ''
    exec ${lib.getExe pkgs.mcp-gateway} serve --stdio -c "''${DEVENV_ROOT}/${stableConfigLink}"
  '';
in
{
  options.kdn.mcp = {
    enable = lib.mkEnableOption "mcp-gateway aggregating MCP servers";

    programs = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "mcp-servers-nix program declarations, same interface as mcp-servers.programs.";
      example = lib.literalExpression ''
        {
          git.enable = true;
          filesystem = { enable = true; args = [ "." ]; };
          github.enable = true;
        }
      '';
    };

    extraBackends = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra mcp-gateway backend stanzas merged on top of the auto-translated ones.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 39400;
    };

    commandOverlays = lib.mkOption {
      type = lib.types.listOf (lib.types.functionTo lib.types.str);
      default = [ ];
      description = ''
        List of command transformers applied left-to-right to the base gateway wrapper command.
        Each function receives the current command string and returns a new command string.
        Use this to wrap the gateway in a proxy (e.g. mcpsnoop) without duplicating the base command.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    kdn.mcp.programs.filesystem.enable = true;
    kdn.mcp.programs.filesystem.args = [ "/nix/store" ];
    kdn.mcp.programs.sequential-thinking.enable = true;
    kdn.mcp.programs.time.enable = true;
    kdn.mcp.programs.fetch.enable = true;

    devenv = {
      packages = [ pkgs.mcp-gateway ];

      # Update the stable symlink on every shell activation.
      enterShell = ''
        ln -sfn ${gatewayConfig} "$DEVENV_ROOT/${stableConfigLink}"
      '';

      # Register only the gateway with Claude Code via stdio — not individual servers.
      # commandOverlays allows other slots to wrap the command (e.g. mcp/snoop).
      claude.code.mcpServers.mcp-gateway = {
        type = "stdio";
        command = lib.pipe "${gatewayWrapper}" cfg.commandOverlays;
      };
    };
  };
}

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
    # The baseline backends, each a `lib.mkDefault`. A consumer drops one with a plain `false`,
    # or names its own `args`. Measured: `attrsOf anything` carries the priority to every leaf.
    kdn.mcp.programs.filesystem.enable = lib.mkDefault true;
    kdn.mcp.programs.filesystem.args = lib.mkDefault [ "/nix/store" ];
    kdn.mcp.programs.sequential-thinking.enable = lib.mkDefault true;
    kdn.mcp.programs.time.enable = lib.mkDefault true;
    kdn.mcp.programs.fetch.enable = lib.mkDefault true;

    # Pin these two servers to nixpkgs' own packages. `mcp-servers-nix` reads the unversioned
    # `typescript` attribute, which nixpkgs moved to TypeScript 7 on 2026-09-01. TypeScript 7 drops
    # the automatic `node_modules/@types/*` include, so both builds fail with `TS2591: Cannot find
    # name 'process'`. nixpkgs fixed its own two copies with a `postPatch` that writes
    # `types: ["node"]`. This `pkgs` holds no `mcp-servers-nix` overlay, so the two bare names below
    # reach the fixed packages. Both are in the binary cache, so this costs no build time.
    kdn.mcp.programs.filesystem.package = lib.mkDefault pkgs.mcp-server-filesystem;
    kdn.mcp.programs.sequential-thinking.package = lib.mkDefault pkgs.mcp-server-sequential-thinking;

    devenv = {
      packages = [ pkgs.mcp-gateway ];

      # Update the stable symlink on every shell activation.
      enterShell = ''
        ln -sfn ${gatewayConfig} "$DEVENV_ROOT/${stableConfigLink}"
      '';

      # Make the inert `programs` translation visible. `mcp-servers-nix` is unreachable from this
      # slot: `flake.mkSlots` (flake.nix) hardwires `specialArgs.inputs` to the `flake.nix` input
      # set, and the input is declared in `devenv.yaml` only. So `mcp-servers-nix` above is null,
      # `servers` is empty, and every enabled `kdn.mcp.programs` entry reaches no backend.
      #
      # This is a warning, never an assertion. An assertion would stop the evaluation of every
      # consumer today, this repository's own devenv shell included. `modules/den/aspects/mcp.nix`
      # warns in the same way for its own null `kdn.mcp.serversNix`.
      #
      # A consumer that declares no enabled program stays silent. `extraBackends` alone is a
      # correct setup, so it must raise nothing.
      warnings =
        let
          inert = lib.attrNames (
            lib.filterAttrs (_: program: (program.enable or false) == true) cfg.programs
          );
        in
        lib.optional (mcp-servers-nix == null && inert != [ ]) ''
          kdn.mcp: the mcp-servers-nix source is missing, so ${toString (builtins.length inert)} declared backend(s) reach no gateway: ${lib.concatStringsSep ", " inert}.
          Cause: modules/slots/mcp/default.nix reads inputs.mcp-servers-nix. flake.mkSlots in
          flake.nix passes the flake.nix input set, and mcp-servers-nix is declared in devenv.yaml
          only. The input is therefore null and the whole kdn.mcp.programs translation is inert.
          Only kdn.mcp.extraBackends reaches the gateway now.
          Fix: give this slot the mcp-servers-nix source. Add the input to flake.nix, or declare a
          kdn.mcp.serversNix option as modules/den/aspects/mcp.nix does and pass your own source.
          To silence this warning instead, set each name above to enable = false.
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

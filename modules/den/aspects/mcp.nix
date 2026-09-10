# The `mcp` slot, as a den aspect. It ports `modules/slots/mcp/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs one `mcp-gateway` process and registers only that process with Claude Code. The gateway
# fans out to every declared backend. Claude Code then sees about 14 meta-tools, and not one tool
# per backend, so the tool surface stays small no matter how many backends exist.
#
# The gateway reads a YAML file. The aspect generates that file into the store, and points a stable
# in-project symlink at it on shell entry. `.mcp.json` then never changes between builds.
#
# ## The family
#
# Four aspects hold what four slot files held:
#
# | Aspect | What it adds |
# |---|---|
# | `mcp` (this file) | the gateway, the YAML, the Claude Code registration |
# | `mcp-snoop` | a JSON-RPC inspector in front of the gateway |
# | `mcp-pretty-print` | a readable approval dialog for a `gateway_invoke` call |
# | `mcp-basic-memory` | one knowledge-base backend per consumer entry, plus its approval preview |
#
# Each child names this aspect in its own `includes`, so an entity includes a child alone. den
# dedupes the diamond. Measured on 2026-09-10: two children that both include this aspect give one
# copy of this module, and its option declarations evaluate exactly once. den keys each target
# module per aspect, and the module system drops a repeated key.
#
# **No child carries an `enable` option.** The slots `mcp/snoop` and `mcp/pretty-print` both default
# `enable = true`, against this repository's own side-effect-free rule. Inclusion is the switch here,
# so that default disappears.
#
# ## `mcp-servers-nix` is a consumer value, not an input
#
# The slot reads `inputs.mcp-servers-nix`. That input lives in `devenv.yaml` only, never in
# `flake.nix`, so no den evaluation can reach it. `kdn.mcp.serversNix` takes the source as a plain
# option instead, and the consumer passes its own. An adopter then needs no input of ours, and this
# repository keeps its lock files unchanged.
#
# When the option stays null, the `programs` declarations reach no backend and `extraBackends` alone
# feeds the gateway. A warning names that state, because a silent empty backend list is the exact
# failure this tree tries to remove.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** A target module below takes `config`, `lib` and `pkgs` only —
#    the arguments every NixOS, nix-darwin, home-manager and devenv evaluation already gives. An
#    argument such as `inputs` or `kdnConfig` would force the consumer to pass `specialArgs`, and
#    that machinery is the whole reason this tree exists. Capture such a value in **this file's**
#    own arguments instead, and close over it.
{ ... }:
{
  kdn.mcp.devenv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.mcp;

      # `mcp-servers-nix` resolves the `programs` declarations into a server set, keyed by name.
      # Its own `lib` exposes `evalModule pkgs <module>`. A null source gives an empty set.
      servers =
        if cfg.serversNix == null then
          { }
        else
          ((import "${cfg.serversNix}/lib").evalModule pkgs {
            inherit (cfg) programs;
            settings = { };
            flavor = "claude-code";
          }).config.settings.servers or { };

      # Translate one `mcp-servers-nix` server entry into one mcp-gateway backend stanza.
      #
      # The gateway takes a single command string, so the arguments fold into it. Every argument is
      # shell-escaped, because a path with a space would otherwise split into two arguments.
      toBackend =
        name: server:
        let
          type = server.type or "stdio";
          isHttp = type == "http" || type == "sse";
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

      gatewayConfig = (pkgs.formats.yaml { }).generate "mcp-gateway.yaml" {
        server = {
          inherit (cfg) host port;
        };
        meta_mcp = {
          enabled = true;
          cache_tools = true;
          cache_ttl = "300s";
        };
        backends = cfg.backends;
      };

      # A stable in-project path, so `.mcp.json` holds one command string for ever. `enterShell`
      # repoints the symlink; the wrapper expands `DEVENV_ROOT` at run time.
      stableConfigLink = ".devenv/mcp-gateway.yaml";

      gatewayWrapper = pkgs.writeShellScript "mcp-gateway-wrapper" ''
        exec ${lib.getExe pkgs.mcp-gateway} serve --stdio -c "''${DEVENV_ROOT}/${stableConfigLink}"
      '';
    in
    {
      options.kdn.mcp = {
        serversNix = lib.mkOption {
          type = lib.types.nullOr lib.types.raw;
          default = null;
          description = ''
            The `mcp-servers-nix` flake source, for example `inputs.mcp-servers-nix`. A plain path to
            a checkout works too. The aspect imports `<source>/lib` and calls `evalModule` on it.

            `null` turns the translation off. `programs` then reaches no backend, and
            `extraBackends` alone feeds the gateway.
          '';
        };

        programs = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = ''
            `mcp-servers-nix` program declarations. Same interface as `mcp-servers.programs`.
            `kdn.mcp.serversNix` must hold a source, or every entry here stays inert.
          '';
          example = lib.literalExpression ''
            {
              git.enable = true;
              filesystem = {
                enable = true;
                args = [ "." ];
              };
            }
          '';
        };

        extraBackends = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = ''
            Extra mcp-gateway backend stanzas, merged on top of the translated ones. A sibling aspect
            adds a backend here — see `mcp-basic-memory`.
          '';
        };

        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address the gateway binds when it runs as a server.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 39400;
          description = "Port the gateway binds when it runs as a server.";
        };

        commandOverlays = lib.mkOption {
          type = lib.types.listOf (lib.types.functionTo lib.types.str);
          default = [ ];
          description = ''
            Command transformers, applied left to right to the base gateway wrapper command. Each
            function takes the current command string and returns a new one.

            An aspect uses this to wrap the gateway in a proxy, and it needs no copy of the base
            command. `mcp-snoop` is the one user in this tree.
          '';
        };

        backends = lib.mkOption {
          type = lib.types.attrsOf lib.types.raw;
          readOnly = true;
          description = ''
            The resolved backend set that the generated YAML holds: the translated `programs` set,
            with `extraBackends` merged on top.

            Read-only, and declared so a test reads one backend stanza with no build and no YAML
            parse. `../../../checks/den-mvp/tests.nix` does exactly that.
          '';
        };
      };

      config = {
        kdn.mcp.backends = (lib.mapAttrs toBackend servers) // cfg.extraBackends;

        # The baseline backends. Each one is read-only or local, and none needs a credential.
        kdn.mcp.programs.filesystem.enable = true;
        kdn.mcp.programs.filesystem.args = [ "/nix/store" ];
        kdn.mcp.programs.sequential-thinking.enable = true;
        kdn.mcp.programs.time.enable = true;
        kdn.mcp.programs.fetch.enable = true;

        packages = [ pkgs.mcp-gateway ];

        # Repoint the stable symlink on every shell activation. This is the one place the aspect
        # writes into the project directory, and it runs on shell entry only — never in a check.
        enterShell = ''
          ln -sfn ${gatewayConfig} "$DEVENV_ROOT/${stableConfigLink}"
        '';

        claude.code.enable = lib.mkDefault true;

        # Register the gateway alone, never one entry per backend. `commandOverlays` lets a sibling
        # aspect wrap the command.
        claude.code.mcpServers.mcp-gateway.type = "stdio";
        claude.code.mcpServers.mcp-gateway.command = lib.pipe "${gatewayWrapper}" cfg.commandOverlays;

        warnings = lib.optional (cfg.serversNix == null) ''
          kdn.mcp.serversNix is null, so every kdn.mcp.programs declaration stays inert and only
          kdn.mcp.extraBackends reaches the gateway. Set kdn.mcp.serversNix to your own
          mcp-servers-nix source to turn the translation on.
        '';

        # The aspect's own smoke test. It travels with the aspect, so an adopter gets it too.
        #
        # devenv puts this in `config.enterTest`, and `config.test` wraps it as a script. It runs
        # under `devenv test` and under `checks.<system>.den-smoke-*`. It does **not** run on shell
        # entry, and it never runs during a nix-darwin or a NixOS activation.
        #
        # Keep every assertion offline. The check runs in the build sandbox, which has no network
        # and no real `$HOME`. So the gateway never starts here; the test reads the generated file.
        enterTest = ''
          echo "• mcp: the gateway binary is on PATH" >&2
          command -v mcp-gateway >/dev/null

          echo "• mcp: the generated config names the bind address and the port" >&2
          grep -Fq '${cfg.host}' ${gatewayConfig}
          grep -Fq '${toString cfg.port}' ${gatewayConfig}

          echo "• mcp: the wrapper reads the stable symlink" >&2
          grep -Fq '${stableConfigLink}' ${gatewayWrapper}

          echo "• mcp: every backend name reaches the generated config" >&2
          ${lib.concatMapStringsSep "\n          " (
            name: "grep -Fq ${lib.escapeShellArg name} ${gatewayConfig}"
          ) (lib.attrNames cfg.backends)}
        '';
      };
    };
}

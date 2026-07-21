# mcp-gateway pretty-print slot.
#
# Claude Code's built-in "Tool use" approval dialog has no display-template or formatter
# API — no hook output field can rewrite the tool name/arguments it renders. Since
# mcp-gateway's single dispatcher tool means every backend call looks identical in that
# dialog ("Invoke Tool(server: ..., tool: ..., arguments: {...})"), the only way to get a
# readable approval step is to suppress the native dialog and substitute a custom one.
# This slot registers a PermissionRequest hook that does exactly that: it shows a native Tk
# window with a readable preview and Allow/Deny buttons, and returns that decision directly —
# Claude Code never shows its own dialog for a `gateway_invoke` call this hook handles.
#
# Individual MCP slots (jj, basic-memory, devenv, ...) contribute their own preview logic via
# `kdn.mcp.pretty-print.formatters.<name>` instead of this hook hardcoding backend-specific
# logic. Each entry mirrors `environment.etc.<name>` (set `text` for inline Nix-interpolated
# source, or `source` to point at an existing file/derivation) and must be a Python module
# implementing:
#
#   def select(ctx: dict) -> bool: ...   # True if this plugin should preview the call
#   def run(ctx: dict) -> str: ...       # the pretty-printed preview text
#
# where ctx = {server, tool, arguments, session_id}. All entries are assembled into a single
# `pretty_print_plugins` Python package (one subpackage per entry) that the hook script depends
# on; it tries each plugin's select() in module-name order and uses the first match's run()
# output, falling back to a plain JSON dump of the arguments when none match.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.kdn.mcp.pretty-print;
  python = pkgs.python3;

  formatterSubmodule =
    {
      name,
      config,
      options,
      ...
    }:
    {
      options = {
        text = lib.mkOption {
          default = null;
          type = lib.types.nullOr lib.types.lines;
          description = ''
            Body of a Python module implementing the pretty-print plugin contract: a
            `select(ctx) -> bool` function and a `run(ctx) -> str` function. `ctx` is
            `{server, tool, arguments, session_id}`.
          '';
          example = ''
            def select(ctx):
                return ctx["server"] in ("memory-public", "memory-sensitive")


            def run(ctx):
                content = ctx["arguments"].get("content", "")
                return f"```markdown\n{content}\n```"
          '';
        };

        source = lib.mkOption {
          type = lib.types.path;
          description = ''
            Path to the plugin module (an existing file or a derivation), used instead of `text`
            when the plugin needs Nix-interpolated content (e.g. a store path baked in by a
            sibling module).
          '';
        };
      };

      config = {
        source = lib.mkIf (config.text != null) (
          lib.mkDerivedConfig options.text (pkgs.writeText "mcp-gateway-pretty-print-plugin-${name}.py")
        );
      };
    };

  pluginsPackage = python.pkgs.buildPythonPackage {
    pname = "mcp-gateway-pretty-print-plugins";
    version = "0.0.1";
    format = "other";
    dontUnpack = true;

    installPhase = ''
      target="$out/${python.sitePackages}/pretty_print_plugins"
      mkdir -p "$target"
      : > "$target/__init__.py"
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: f: ''
        mkdir -p "$target/${name}"
        ln -s ${f.source} "$target/${name}/__init__.py"
      '') cfg.formatters
    );
  };

in
{
  options.kdn.mcp.pretty-print = {
    enable = lib.mkEnableOption "pretty-printing of mcp-gateway gateway_invoke calls" // {
      default = true;
    };

    formatters = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule formatterSubmodule);
      default = { };
      description = ''
        Per-backend/tool pretty-print plugins for the mcp-gateway hook, keyed by an arbitrary
        name. Sibling MCP slot modules (e.g. basic-memory, jj) contribute entries here instead of
        this hook hardcoding backend-specific logic.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = python.pkgs.buildPythonApplication {
        pname = "mcp-gateway-pretty-print";
        meta.mainProgram = "mcp-gateway-pretty-print";
        version = "0.0.1";
        format = "other";
        dontUnpack = true;

        dependencies = with python.pkgs; [
          pluginsPackage
          tkinter
        ];

        installPhase = ''
          mkdir -p "$out/bin"
          install -m755 ${./mcp_gateway_pretty_print.py} "$out/bin/mcp-gateway-pretty-print"
        '';
      };
      description = ''
        The built `mcp-gateway-pretty-print` hook script, with all `formatters` entries
        assembled onto its PYTHONPATH. Exposed so it can be built/inspected directly from a
        consuming devenv.nix, e.g. `devenv build slots.kdn.mcp.pretty-print.package` (via the
        `slots` passthrough documented in lib/slots/default.nix).
      '';
    };
  };

  config = lib.mkIf (config.kdn.mcp.enable && cfg.enable) {
    devenv = {
      packages = [ cfg.package ];

      claude.code.enable = true;
      claude.code.hooks.mcp-gateway-pretty-print = {
        hookType = "PermissionRequest";
        matcher = "mcp__mcp-gateway__gateway_invoke";
        command = lib.getExe cfg.package;
      };
    };
  };
}

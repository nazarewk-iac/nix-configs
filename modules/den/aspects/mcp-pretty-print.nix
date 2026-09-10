# The `mcp/pretty-print` slot, as a den aspect. It ports `modules/slots/mcp/pretty-print/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## Why the aspect exists
#
# Claude Code's own approval dialog has no display template and no formatter API. No hook output
# field rewrites the tool name or the arguments it prints. The gateway has one dispatcher tool, so
# every backend call looks the same there: `Invoke Tool(server: ..., tool: ..., arguments: {...})`.
#
# So the aspect registers a `PermissionRequest` hook that replaces that dialog. The hook shows a Tk
# window with a readable preview and an Allow button and a Deny button, and it returns that decision
# directly. Claude Code shows no dialog of its own for a `gateway_invoke` call the hook handles.
#
# ## How a sibling aspect adds a preview
#
# `kdn.mcp.pretty-print.formatters.<name>` takes one Python module per backend. Each entry mirrors
# `environment.etc.<name>`: set `text` for inline content, or `source` for a file or a derivation.
# A module implements two functions:
#
#   def select(ctx: dict) -> bool: ...   # True when this plugin previews the call
#   def run(ctx: dict) -> str: ...       # the preview text
#
# `ctx` is `{ server, tool, arguments, session_id }`. Every entry becomes one subpackage of a single
# `pretty_print_plugins` Python package. The hook tries each `select()` in module-name order, uses
# the first match, and falls back to a plain JSON dump of the arguments.
#
# `mcp-basic-memory` is the one user in this tree, so this aspect hardcodes no backend name.
#
# ## Two differences from the slot
#
# 1. **No `enable` option.** The slot defaults `kdn.mcp.pretty-print.enable = true`, against this
#    repository's own side-effect-free rule. Inclusion is the switch here.
# 2. **The hook script comes from the slot tree.** `mcp_gateway_pretty_print.py` still lives beside
#    the slot. A relative path reads it, so no copy can drift; a dangling path fails loudly, and a
#    duplicate would not. The file moves next to this aspect when the slot tree goes away — logged
#    in ../../../docs/tasks/2026-09/generalization/009-personal-data-folder/definition.md.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** A target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
{
  kdn.mcp-pretty-print.includes = [ kdn.mcp ];

  kdn.mcp-pretty-print.devenv =
    {
      config,
      lib,
      pkgs,
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
          options.text = lib.mkOption {
            default = null;
            type = lib.types.nullOr lib.types.lines;
            description = ''
              Body of a Python module that implements the plugin contract: a `select(ctx) -> bool`
              function and a `run(ctx) -> str` function. `ctx` is
              `{ server, tool, arguments, session_id }`.
            '';
            example = ''
              def select(ctx):
                  return ctx["server"] == "memory-public"


              def run(ctx):
                  return ctx["arguments"].get("content", "")
            '';
          };

          options.source = lib.mkOption {
            type = lib.types.path;
            description = ''
              Path to the plugin module — an existing file or a derivation. Use it instead of `text`
              when the plugin needs content that Nix interpolates, for example a store path that a
              sibling aspect bakes in.
            '';
          };

          config.source = lib.mkIf (config.text != null) (
            lib.mkDerivedConfig options.text (pkgs.writeText "mcp-gateway-pretty-print-plugin-${name}.py")
          );
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
        formatters = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule formatterSubmodule);
          default = { };
          description = ''
            One pretty-print plugin per backend or tool, keyed by an arbitrary name. A sibling aspect
            adds an entry here, so this hook holds no backend-specific logic.
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
              install -m755 ${../../slots/mcp/pretty-print/mcp_gateway_pretty_print.py} \
                "$out/bin/mcp-gateway-pretty-print"
            '';
          };
          description = ''
            The built hook script, with every `formatters` entry on its `PYTHONPATH`. Declared as an
            option so a consumer inspects or builds it directly.
          '';
        };
      };

      config = {
        packages = [ cfg.package ];

        claude.code.enable = lib.mkDefault true;
        claude.code.hooks.mcp-gateway-pretty-print = {
          hookType = "PermissionRequest";
          matcher = "mcp__mcp-gateway__gateway_invoke";
          command = lib.getExe cfg.package;
        };

        # Offline assertions only. The hook needs a display to draw its window, so the test never
        # runs it — it reads the built files instead.
        enterTest = ''
          echo "• mcp-pretty-print: the hook binary is on PATH" >&2
          command -v mcp-gateway-pretty-print >/dev/null

          echo "• mcp-pretty-print: every formatter lands in the plugin package" >&2
          ${lib.concatMapStringsSep "\n          " (
            name: "test -e ${pluginsPackage}/${python.sitePackages}/pretty_print_plugins/${name}/__init__.py"
          ) (lib.attrNames cfg.formatters)}
        '';
      };
    };
}

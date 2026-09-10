# The `opencode` slot, as a den aspect. It ports `modules/slots/opencode/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns on devenv's own `opencode` integration, so devenv writes a project-level
# `opencode.jsonc`. opencode deep-merges that file over the user's global configuration, so a
# value this aspect does not set stays as the user set it.
#
# It also puts **one** binary named `opencode` on PATH: a wrapper. The wrapper exports the
# credentials, then it execs the real opencode by absolute store path. The real binary never
# reaches the bare PATH, so a plain `opencode` call can never skip the credential step.
# `KDN_OPENCODE_WRAPPER=1` tells the running opencode that a wrapper started it.
#
# ## The aspect holds the shape; the consumer holds the data
#
# The slot hardcodes three of the creator's own values: one commercial provider name in the
# credential read, that same provider in the default `settings`, and the creator's checkout path
# `~/dev/**` in five permission blocks. This aspect names none of them. It declares an option for
# each, and the consumer supplies the value:
#
# | Data | Option |
# |---|---|
# | which provider key to read, and into which environment variable | `kdn.opencode.authKeys` |
# | which provider block to write | `kdn.opencode.settings` |
# | which paths a tool may reach with no question | `kdn.opencode.allowedPaths` |
#
# The creator stated this constraint on 2026-09-10: an aspect stays universal, and the data stays
# with the consumer. See ../../../docs/tasks/2026-09/generalization/009-personal-data-folder/definition.md.
#
# ## One behaviour that differs from the slot, on purpose
#
# The slot puts the permission baseline **inside** the `settings` default. A `default` disappears
# the moment any definition exists, so a consumer that sets one provider silently loses the whole
# baseline. This aspect merges the baseline in the `config` instead. So the baseline always applies,
# and a consumer overrides it only by setting `settings.permission` itself.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. So an inclusion means "this shell runs
#    opencode".
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  den.aspects.opencode.devenv =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.opencode;

      # The permission baseline. It is a policy, not personal data: it asks before every write and
      # before every reach outside the project, and it allows a read of the paths the consumer
      # named. `lib.genAttrs` keeps the four read-only tools in step with one list.
      allowMap = lib.listToAttrs (map (p: lib.nameValuePair p "allow") cfg.allowedPaths);

      defaultPermission = {
        external_directory = {
          "*" = "ask";
        }
        // allowMap;
        edit = "ask";
        bash = {
          "cat *" = "allow";
          "ls *" = "allow";
          "grep *" = "allow";
          "rg *" = "allow";
          "head *" = "allow";
          "tail *" = "allow";
          "wc *" = "allow";
          "sort *" = "allow";
          "find *" = "allow";
          "stat *" = "allow";
          "file *" = "allow";
          "git status*" = "allow";
          "*" = "ask";
        };
      }
      // lib.genAttrs [
        "read"
        "glob"
        "grep"
        "list"
      ] (_: allowMap);

      # One export per credential. Each value is a provider id in opencode's own `auth.json`, so
      # the jq filter reads `.<provider>.key`. An empty attribute set emits no line at all, so the
      # aspect names no provider by itself.
      authExports = lib.mapAttrsToList (name: provider: ''
        export ${name}="$(${lib.getExe pkgs.jq} -r ${lib.escapeShellArg ".${provider}.key // empty"} ${cfg.authFile} 2>/dev/null || true)"
        if [ -z "''${${name}:-}" ]; then
          echo "opencode: the kdn wrapper found no ${provider} key in ${cfg.authFile}" >&2
        fi
      '') cfg.authKeys;

      opencodeBin = pkgs.writeShellScriptBin "opencode" ''
        set -euo pipefail
        export KDN_OPENCODE_WRAPPER=1
        ${lib.concatStringsSep "\n" authExports}
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") cfg.wrapper.env
        )}
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: path: ''export ${name}="$(cat ${path})"'') cfg.wrapper.envFiles
        )}
        ${cfg.wrapper.preExec}
        exec ${lib.getExe cfg.package} "$@"
      '';
    in
    {
      options.kdn.opencode.package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.opencode;
        defaultText = lib.literalExpression "pkgs.opencode";
        description = ''
          The real opencode binary that the wrapper execs. It never reaches the bare PATH; the
          wrapper carries the name `opencode` instead.
        '';
      };

      options.kdn.opencode.defaultModel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "some-provider/some-model";
        description = ''
          The model written to `opencode.jsonc` as `model`. When null, the key stays out of the
          file, so an existing model choice keeps its value.
        '';
      };

      options.kdn.opencode.settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        example = lib.literalExpression ''
          {
            provider.some-provider = { };
          }
        '';
        description = ''
          The content of `opencode.jsonc`, written verbatim. The permission baseline merges under
          it, so a `permission` key here replaces the baseline in full.
        '';
      };

      options.kdn.opencode.allowedPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "/nix/store/**" ];
        example = [
          "/nix/store/**"
          "~/src/**"
        ];
        description = ''
          The path globs that a read-only tool reaches with no question. Each glob lands in the
          `external_directory`, `read`, `glob`, `grep` and `list` permission blocks as `allow`.

          The default names the store only. Add your own checkout root here.
        '';
      };

      options.kdn.opencode.authFile = lib.mkOption {
        type = lib.types.str;
        default = "$HOME/.local/share/opencode/auth.json";
        description = ''
          The file that `authKeys` reads. This is opencode's own credential store, so the default
          fits every installation. The value goes into a shell script, so a `$HOME` reference works.
        '';
      };

      options.kdn.opencode.authKeys = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = {
          SOME_PROVIDER_API_KEY = "some-provider";
        };
        description = ''
          Environment variable name to provider id. The wrapper reads `.<provider>.key` from
          `authFile` and exports the value. An empty set exports nothing.
        '';
      };

      options.kdn.opencode.wrapper = lib.mkOption {
        type = lib.types.submodule {
          options.env = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Literal `NAME=VALUE` exports that the wrapper sets before it execs.";
          };
          options.envFiles = lib.mkOption {
            type = lib.types.attrsOf lib.types.path;
            default = { };
            description = "Environment name to file path. The wrapper exports the file content.";
          };
          options.preExec = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Extra shell lines that the wrapper runs before it execs opencode.";
          };
        };
        default = { };
        description = ''
          Extensions to the single wrapper. Another aspect adds an environment variable or a step
          here, so no consumer needs a second wrapper of its own.
        '';
      };

      config = {
        opencode.enable = true;

        # `//` order matters. The baseline goes in first, so `cfg.settings.permission` replaces it.
        # `model` goes in last, and only when the consumer named one.
        opencode.settings = {
          permission = defaultPermission;
        }
        // cfg.settings
        // lib.optionalAttrs (cfg.defaultModel != null) { model = cfg.defaultModel; };

        packages = [ opencodeBin ];

        # The aspect's own smoke test. It stays offline: the sandbox has no network and no real
        # `$HOME`, so nothing here starts opencode itself.
        enterTest = ''
          echo "• opencode: the binary on PATH is the wrapper" >&2
          test -x "$(command -v opencode)"
          grep -q 'KDN_OPENCODE_WRAPPER=1' "$(command -v opencode)"

          echo "• opencode: the wrapper execs a store path" >&2
          grep -qE '^exec /nix/store/' "$(command -v opencode)"
        '';
      };
    };
}

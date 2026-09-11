# OpenCode slot — generalized in-devenv opencode capability.
#
# Generates a project-level `opencode.jsonc` via devenv's native
# `opencode.settings` option, so opencode running inside the devenv shell is
# configured declaratively (model, providers, permissions) instead of relying on
# a hand-edited global `~/.config/opencode/opencode.jsonc`. opencode deep-merges
# this project config over the global one, so anything not set here still
# applies.
#
# This slot is intentionally BARE: it exposes the capability (the
# `opencode.jsonc` generation and an `opencode` wrapper that authenticates) but
# declares no specific providers, models, or upstreams itself. The consumer
# supplies those via the `settings` option (a free-form attrset that is
# written to `opencode.jsonc` verbatim). This keeps the slot harmless when
# enabled globally — only hosts that populate `settings` (e.g. a
# hostname-scoped devenv profile) get a rich, model-carrying config.
#
# The `settings` default is empty, so a global enable stays harmless and the slot
# names no provider. The permission baseline merges under `settings`, and
# `kdn.opencode.allowedPaths` states which path globs a read-only tool reaches.
# Consumers extend `settings` with the providers they want to use.
#
# The `opencode` binary on PATH is itself the wrapper: it reads every credential
# named in `kdn.opencode.authKeys` from `kdn.opencode.authFile` via jq, applies
# the extensible `kdn.opencode.wrapper` (env / envFiles / preExec) secret/step
# injection, then execs the real `pkgs.opencode` by absolute store path. The
# real binary is kept off the bare PATH so running `opencode` always activates
# the wrapper — you cannot accidentally run the naked binary and forget the
# key. KDN_OPENCODE_WRAPPER=1 is exported so running opencode knows it is the
# wrapper.
#
# This slot is STANDALONE. It uses only `lib`, `pkgs`, `config`, and plain
# devenv options (opencode.*, packages). It never references or assigns an
# option declared by modules/universal/ or modules/meta/. See
# .agents/rules/slots-standalone.md.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.opencode;

  # The permission baseline. It is a policy, not personal data: it asks before every write and
  # before every reach outside the project, and it allows a read of the paths the consumer names.
  # `lib.genAttrs` keeps the four read-only tools in step with one list.
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

  # One export per credential. Each value is a provider id in opencode's own `auth.json`, so the
  # jq filter reads `.<provider>.key`. An empty attribute set emits no line, so the slot names no
  # provider by itself.
  authExports = lib.mapAttrsToList (name: provider: ''
    export ${name}="$(${lib.getExe pkgs.jq} -r ${lib.escapeShellArg ".${provider}.key // empty"} "${cfg.authFile}" 2>/dev/null || true)"
    if [ -z "''${${name}:-}" ]; then
      echo "opencode: the kdn wrapper found no ${provider} key in ${cfg.authFile}" >&2
    fi
  '') cfg.authKeys;

  # Single opencode entrypoint, assembled from the extensible `wrapper` option.
  # Base: reads every credential named in `authKeys` from `authFile` via jq. Then:
  #   - exports every literal `wrapper.env` (NAME=VALUE)
  #   - exports every `wrapper.envFiles` entry by reading the file (NAME=$(cat)
  #   - runs `wrapper.preExec` (extra shell lines)
  # This lets consumer modules (e.g. a LAN LLM client) extend the wrapper's
  # env/pre-exec behaviour instead of the slot enumerating every use-case.
  # The wrapper IS the `opencode` binary on PATH: the real opencode is only
  # reached via its absolute store path below, so a bare `opencode` in the
  # shell always activates the wrapper (key/env injection) rather than a naked
  # binary that would forget to auth. KDN_OPENCODE_WRAPPER=1 is exported so a
  # running opencode (and its hooks/scripts) knows it is under the wrapper.
  opencodeBin = pkgs.writeShellScriptBin "opencode" ''
    set -euo pipefail
    export KDN_OPENCODE_WRAPPER=1
    ${lib.concatStringsSep "\n" authExports}
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") cfg.wrapper.env
    )}
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: path: "export ${name}=\"$(cat ${path})\"") cfg.wrapper.envFiles
    )}
    ${cfg.wrapper.preExec}
    exec ${lib.getExe cfg.package} "$@"
  '';
in
{
  options.kdn.opencode = {
    enable = lib.mkEnableOption "in-devenv opencode configuration (opencode.jsonc + wrapper)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.opencode;
      description = "The real opencode binary the kdn wrapper execs. NOT put on bare PATH; the wrapper (named `opencode`) is.";
    };

    # Default selected model, optional. When null (default), no `model` is set
    # in the emitted opencode.jsonc, so an existing model selection is never
    # overridden. Set to a specific provider/model to make it the default.
    defaultModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default model written to opencode.jsonc when set; omitted when null.";
    };

    # The content written to `opencode.jsonc` (provider, permission, ...). The
    # default is empty, so the slot names no provider of its own. The permission
    # baseline merges under this value in `config` below, so a `permission` key
    # here replaces the baseline in full. The `model` key comes from
    # `defaultModel`, and only when that option is set.
    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = lib.literalExpression ''
        {
          provider.some-provider = { };
        }
      '';
      description = "opencode config written to opencode.jsonc (provider, permission, ...).";
    };

    allowedPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/nix/store/**" ];
      example = [
        "/nix/store/**"
        "~/src/**"
      ];
      description = ''
        Path globs that a read-only tool reaches with no question. Each glob lands
        in the `external_directory`, `read`, `glob`, `grep` and `list` permission
        blocks as `allow`. The default names the store only. Add your own checkout
        root here.
      '';
    };

    authFile = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/.local/share/opencode/auth.json";
      description = ''
        The file that `authKeys` reads. This is opencode's own credential store, so
        the default fits every installation. The value goes into a shell script, so
        a `$HOME` reference works.
      '';
    };

    authKeys = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        SOME_PROVIDER_API_KEY = "some-provider";
      };
      description = ''
        Environment variable name to provider id. The wrapper reads
        `.<provider>.key` from `authFile` and exports the value. An empty set
        exports nothing.
      '';
    };

    # Extensions to the `opencode` wrapper (which is the `opencode` binary on
    # PATH). Data-driven so any consumer module can extend the single entrypoint
    # (env injection, pre-exec steps) without a per-upstream wrapper. Emitted
    # roughly as:
    #   export NAME=VALUE                      (wrapper.env)
    #   export NAME="$(cat /path)"             (wrapper.envFiles)
    #   <wrapper.preExec>
    #   exec <real opencode absolute path> "$@"
    # Self-signed CA trust is handled system-wide (security.pki), so no
    # NODE_EXTRA_CA_CERTS injection is needed here.
    wrapper = lib.mkOption {
      type = lib.types.submodule {
        options = {
          env = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Literal NAME=VALUE exports set by the opencode wrapper before exec.";
          };
          envFiles = lib.mkOption {
            type = lib.types.attrsOf lib.types.path;
            default = { };
            description = "env NAME -> file path; the opencode wrapper exports NAME as the file contents.";
          };
          preExec = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Extra shell lines run by the opencode wrapper before exec'ing opencode.";
          };
        };
      };
      default = { };
      description = "Extensions to the opencode wrapper (env, env-files, pre-exec).";
    };
  };

  config = lib.mkIf cfg.enable {
    devenv = {
      opencode.enable = true;
      # `//` order matters. The baseline goes in first, so `cfg.settings.permission`
      # replaces it. `model` goes in last, and only when the consumer named one.
      opencode.settings = {
        permission = defaultPermission;
      }
      // cfg.settings
      // lib.optionalAttrs (cfg.defaultModel != null) {
        model = cfg.defaultModel;
      };

      packages = [
        opencodeBin
      ];
    };
  };
}

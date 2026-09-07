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
# A benign default `settings` skeleton is provided so a global enable is
# harmless: a native provider only (no proxy dependency), a working default
# model, and the permission block. Consumers override/extend `settings` to add
# the proxied/local providers they actually want to use.
#
# The `opencode` binary on PATH is itself the wrapper: it loads
# REQUESTY_API_KEY from ~/.local/share/opencode/auth.json via jq, applies the
# extensible `kdn.opencode.wrapper` (env / envFiles / preExec) secret/step
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
}: let
  cfg = config.kdn.opencode;

  # Default permission policy. Kept in the slot as a global default so any host
  # using this devenv gets a consistent, safe baseline. TODO: revisit whether
  # this belongs in the slot or should be moved to the consumer.
  defaultPermission = {
    external_directory = {
      "*" = "ask";
      "/nix/store/**" = "allow";
      "~/dev/**" = "allow";
    };
    read = {
      "/nix/store/**" = "allow";
      "~/dev/**" = "allow";
    };
    glob = {
      "/nix/store/**" = "allow";
      "~/dev/**" = "allow";
    };
    grep = {
      "/nix/store/**" = "allow";
      "~/dev/**" = "allow";
    };
    list = {
      "/nix/store/**" = "allow";
      "~/dev/**" = "allow";
    };
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
  };

  # Single opencode entrypoint, assembled from the extensible `wrapper` option.
  # Base: loads REQUESTY_API_KEY from opencode's auth.json (via jq) for a
  # `requesty-proxy` provider. Then:
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
    export REQUESTY_API_KEY="$(${lib.getExe pkgs.jq} -r '.requesty.key // empty' "$HOME/.local/share/opencode/auth.json" 2>/dev/null || true)"
    if [ -z "''${REQUESTY_API_KEY:-}" ]; then
      echo "opencode: running via the KDN wrapper but no requesty key in ~/.local/share/opencode/auth.json" >&2
    fi
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") cfg.wrapper.env)}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: path: "export ${name}=\"$(cat ${path})\"") cfg.wrapper.envFiles)}
    ${cfg.wrapper.preExec}
    exec ${lib.getExe cfg.package} "$@"
  '';
in {
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

    # The content written to `opencode.jsonc` (provider, permission, ...).
    # Defaults to a benign skeleton so a global enable is harmless; consumers
    # (e.g. a hostname-scoped devenv profile) override with their real providers
    # and models. mkDefault lets a consumer's normal-priority assignment win.
    # The `model` key is injected from `defaultModel` only when that is set, so
    # it is not emitted (and never overrides a prior selection) by default.
    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = lib.mkDefault {
        provider.requesty = {};
        permission = defaultPermission;
      };
      description = "opencode config written to opencode.jsonc (provider, permission, ...).";
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
            default = {};
            description = "Literal NAME=VALUE exports set by the opencode wrapper before exec.";
          };
          envFiles = lib.mkOption {
            type = lib.types.attrsOf lib.types.path;
            default = {};
            description = "env NAME -> file path; the opencode wrapper exports NAME as the file contents.";
          };
          preExec = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Extra shell lines run by the opencode wrapper before exec'ing opencode.";
          };
        };
      };
      default = {};
      description = "Extensions to the opencode wrapper (env, env-files, pre-exec).";
    };
  };

  config = lib.mkIf cfg.enable {
    devenv = {
      opencode.enable = true;
      # Inject `model` only when a default model is set; otherwise leave the
      # consumer's settings (and any previous model selection) untouched.
      opencode.settings =
        cfg.settings
        // lib.optionalAttrs (cfg.defaultModel != null) {
          model = cfg.defaultModel;
        };

      packages = [
        opencodeBin
      ];
    };
  };
}

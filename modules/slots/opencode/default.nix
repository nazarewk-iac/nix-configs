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
# `opencode.jsonc` generation, the `opcode-kdn` wrapper, and `pkgs.opencode` on
# PATH) but declares no specific providers, models, or upstreams itself. The
# consumer supplies those via the `settings` option (a free-form attrset that is
# written to `opencode.jsonc` verbatim). This keeps the slot harmless when
# enabled globally — only hosts that populate `settings` (e.g. a
# hostname-scoped devenv profile) get a rich, model-carrying config.
#
# A benign default `settings` skeleton is provided so a global enable is
# harmless: a native provider only (no proxy dependency), a working default
# model, and the permission block. Consumers override/extend `settings` to add
# the proxied/local providers they actually want to use.
#
# The `opencode-kdn` wrapper loads REQUESTY_API_KEY from
# ~/.local/share/opencode/auth.json via jq, then execs the real opencode. It is
# generic and ships with the slot.
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

  # Wrapper that loads REQUESTY_API_KEY from opencode's auth.json (via jq) so
  # a `requesty-proxy` provider — which uses {env:REQUESTY_API_KEY} — can
  # authenticate. Run `opencode-kdn` inside the devenv shell.
  opencodeKdn = pkgs.writeShellScriptBin "opencode-kdn" ''
    set -euo pipefail
    export REQUESTY_API_KEY="$(${lib.getExe pkgs.jq} -r '.requesty.key // empty' "$HOME/.local/share/opencode/auth.json" 2>/dev/null || true)"
    if [ -z "''${REQUESTY_API_KEY:-}" ]; then
      echo "opencode-kdn: no requesty key found in ~/.local/share/opencode/auth.json" >&2
    fi
    exec ${lib.getExe pkgs.opencode} "$@"
  '';
in
{
  options.kdn.opencode = {
    enable = lib.mkEnableOption "in-devenv opencode configuration (opencode.jsonc + wrapper)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.opencode;
      description = "opencode package to put on PATH.";
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
        provider.requesty = { };
        permission = defaultPermission;
      };
      description = "opencode config written to opencode.jsonc (provider, permission, ...).";
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
        cfg.package
        opencodeKdn
      ];
    };
  };
}

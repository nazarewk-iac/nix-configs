# OpenCode slot — owns the in-devenv opencode configuration.
#
# Generates the project-level `opencode.jsonc` via devenv's native
# `opencode.settings` option, so opencode running inside the devenv shell is
# configured declaratively (model, providers, permissions) instead of relying on
# a hand-edited global `~/.config/opencode/opencode.jsonc`. opencode deep-merges
# this project config over the global one, so anything not set here (e.g. a
# global permission rule) still applies.
#
# Providers:
#   - `requesty`        native requesty, direct API (auth from auth.json)
#   - `requesty-proxy`  requesty routed through the DSML proxy (:9532);
#                       needs REQUESTY_API_KEY (set by the opencode-kdn wrapper)
#   - `local-llm-proxy` local llama-swap model routed through the DSML proxy
#                       (:9533); no auth
#
# The `opencode-kdn` wrapper is shipped here (it belongs with opencode, not with
# the proxy infra). It loads REQUESTY_API_KEY from ~/.local/share/opencode/auth.json
# via jq, then execs the real opencode.
#
# The local proxy process (upstream 127.0.0.1:39703, the host llama-swap) is
# started as a devenv process so the local model is reachable in the shell.
# The requesty proxy is assumed to be provided by the `kdn.llm.proxy` slot.
#
# This slot is STANDALONE. It uses only `lib`, `pkgs`, `config`, and plain
# devenv options (opencode.*, packages, processes). It never references or
# assigns an option declared by modules/universal/ or modules/meta/. See
# .agents/rules/slots-standalone.md.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.opencode;

  # Wrapper that loads REQUESTY_API_KEY from opencode's auth.json (via jq) so
  # the `requesty-proxy` provider — which uses {env:REQUESTY_API_KEY} — can
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
    enable = lib.mkEnableOption "in-devenv opencode configuration (providers, permissions, model)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.opencode;
      description = "opencode package to put on PATH.";
    };

    requestyProxyBaseURL = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:9532";
      description = "Base URL of the requesty DSML proxy instance (no /v1).";
    };

    localProxyBaseURL = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:9533";
      description = "Base URL of the local DSML proxy instance (no /v1).";
    };

    # Default model id in `provider/model` form.
    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "requesty-proxy/sference/deepseek-v4-flash-0731";
    };

    # Run a local proxy process (upstream = host llama-swap) so the local model
    # is reachable in the shell. Consuming hosts that use the `kdn.llm.proxy`
    # slot may disable this to avoid a duplicate process.
    localProxy.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run the local DSML proxy as a devenv process in this slot.";
    };

    localProxy.upstreamUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:39703";
      description = "Upstream local LLM backend (host llama-swap).";
    };
  };

  config = lib.mkIf cfg.enable {
    devenv = {
      opencode.enable = true;
      opencode.settings = {
        model = cfg.defaultModel;
        provider = {
          # Native requesty — direct API, auth from auth.json.
          requesty = { };
          # Requesty via DSML proxy; needs REQUESTY_API_KEY (see opencode-kdn).
          requesty-proxy = {
            npm = "@ai-sdk/openai-compatible";
            name = "DeepSeek V4 Flash (Requesty via DSML proxy)";
            options = {
              baseURL = "${cfg.requestyProxyBaseURL}/v1";
              apiKey = "{env:REQUESTY_API_KEY}";
            };
            models."sference/deepseek-v4-flash-0731" = {
              name = "deepseek-v4-flash-0731 (proxied)";
              limit.context = 65536;
              limit.output = 8192;
            };
          };
          # Local llama-swap model via the DSML proxy; no auth.
          local-llm-proxy = {
            npm = "@ai-sdk/openai-compatible";
            name = "DeepSeek V4 Flash (local llama-swap via DSML proxy)";
            options = {
              baseURL = "${cfg.localProxyBaseURL}/v1";
              apiKey = "dummy";
            };
            models."deepseek-v4-flash" = {
              name = "deepseek-v4-flash (local)";
              limit.context = 65536;
              limit.output = 8192;
            };
          };
        };
        permission = {
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
      };

      packages = [
        cfg.package
        opencodeKdn
      ];

      processes = lib.mkIf cfg.localProxy.enable {
        "proxy-local-opencode".exec = ''
          UPSTREAM_URL=${cfg.localProxy.upstreamUrl} PROXY_HOST=127.0.0.1 PROXY_PORT=9533 ${lib.getExe pkgs.kdn.opencode-compat-proxy}
        '';
      };
    };
  };
}

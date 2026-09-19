# brys-specific devenv profile.
#
# A profile scoped to the brys host, imported by the primary `devenv.nix` via
# `profiles.hostname."brys".module`. It is a plain devenv module: it imports the den
# aspects it needs and sets their options. The parent shell already imports `opencode`,
# so den collapses the diamond and one wrapper reaches this shell.
#
# It enables the in-devenv opencode capability with the brys-specific model wiring:
#   - requesty routed through the DSML proxy (:9526, forwardClientAuth)
#   - the local llama-swap model routed through a local DSML proxy (:9533)
#
# Only the host whose hostname is `brys` auto-activates this profile, so the rich
# provider/model config is scoped to brys and every other host keeps the benign global
# opencode skeleton.
{
  inputs,
  ...
}:
{
  imports = inputs.nix-configs.denLib.imports {
    class = "devenv";
    aspects = [ "llm-proxy" ];
  };

  # The slot named no credential of its own, so this line keeps the wrapper's
  # REQUESTY_API_KEY export that the `requesty-proxy` provider below reads.
  kdn.opencode.authKeys.REQUESTY_API_KEY = "requesty";
  kdn.opencode.settings = {
    provider = {
      # Native requesty — direct API, auth from auth.json.
      requesty = { };
      # Requesty via DSML proxy; needs REQUESTY_API_KEY (see the opencode wrapper).
      requesty-proxy = {
        npm = "@ai-sdk/openai-compatible";
        name = "DeepSeek V4 Flash (Requesty via DSML proxy)";
        options = {
          baseURL = "http://127.0.0.1:9532/v1";
          apiKey = "{env:REQUESTY_API_KEY}";
        };
        models."sference/deepseek-v4-flash-0731" = {
          name = "deepseek-v4-flash-0731 (proxied)";
          limit.context = 65536;
          limit.output = 8192;
        };
      };
      # Local llama-swap model via the local DSML proxy; no auth.
      local-llm-proxy = {
        npm = "@ai-sdk/openai-compatible";
        name = "DeepSeek V4 Flash (local llama-swap via DSML proxy)";
        options = {
          baseURL = "http://127.0.0.1:9533/v1";
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

  # The model proxies, run as devenv processes on brys.
  kdn.llm.proxy.instances.requesty = {
    enable = true;
    upstreamUrl = "https://router.requesty.ai";
    port = 9526;
    forwardClientAuth = true;
  };
  kdn.llm.proxy.instances.local = {
    enable = true;
    upstreamUrl = "http://127.0.0.1:39703";
    port = 9533;
  };
}

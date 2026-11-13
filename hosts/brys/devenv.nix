# brys-specific devenv profile.
#
# A profile scoped to the brys host, imported by the primary `devenv.nix` via
# `profiles.hostname."brys".module`. It is a plain devenv module: it imports the den
# aspects it needs and sets their options. The parent shell already imports `opencode`,
# so den collapses the diamond and one wrapper reaches this shell.
#
# It enables the in-devenv opencode capability with the brys-specific model wiring:
#   - requesty via the DSML proxy (:9526, forwardClientAuth), hardcoding no model
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

  # The wrapper exports REQUESTY_API_KEY; the `requesty-proxy` provider below reads it.
  kdn.opencode.authKeys.REQUESTY_API_KEY = "requesty";
  kdn.opencode.settings = {
    provider = {
      # Native requesty — direct API, auth from auth.json; no model is hardcoded.
      requesty = { };
      # Requesty via the DSML proxy; needs REQUESTY_API_KEY. No model is hardcoded here: the
      # client discovers the catalog, so a model is never pinned to one that later goes away.
      requesty-proxy = {
        npm = "@ai-sdk/openai-compatible";
        name = "Requesty (via DSML proxy)";
        options = {
          baseURL = "http://127.0.0.1:9532/v1";
          apiKey = "{env:REQUESTY_API_KEY}";
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

  # The model proxy, run as a devenv process on brys.
  kdn.llm.proxy.instances.requesty = {
    enable = true;
    upstreamUrl = "https://router.requesty.ai";
    port = 9526;
    forwardClientAuth = true;
  };
}

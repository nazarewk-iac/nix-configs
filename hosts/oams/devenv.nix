# oams-specific devenv profile.
#
# A profile scoped to the oams host, imported by the primary `devenv.nix` via
# `profiles.hostname."oams".module`. It is a plain devenv module: it imports the den
# aspects it needs and sets their options. The parent shell already imports `opencode`,
# so den collapses the diamond and one wrapper reaches this shell.
#
# It enables opencode (via the parent shell) and feeds the required info to
# `kdn.llm.client`, which writes the opencode provider. The `opencode` wrapper injects the
# brys API key. The self-signed cert is trusted system-wide on oams via the `kdn.ca.kdn`
# slot (security.pki). This file is intentionally minimal.
#
# Only the host whose hostname is `oams` auto-activates this profile.
{
  inputs,
  lib,
  ...
}:
let
  # The common thinking levels. Every model gets one opencode subagent per level,
  # named `<prefix>-<level>`, so a caller picks a model and a thinking depth in
  # one name.
  thinkingLevels = [
    "off"
    "low"
    "medium"
    "high"
  ];

  # Per-model mapping from a level to that model's own `chat_template_kwargs`.
  # opencode sends an agent's `options` object verbatim in the request body, so
  # these reach llama-server unchanged.
  #
  # DS4's template honours only `reasoning_effort = "max"`; it ignores every
  # other value. So `low` and `medium` are equivalent thinking-on, and `high` is
  # the only level that differs (it adds `reasoning_effort = "max"`).
  ds4Thinking = {
    off = {
      enable_thinking = false;
    };
    low = {
      enable_thinking = true;
    };
    medium = {
      enable_thinking = true;
    };
    high = {
      enable_thinking = true;
      reasoning_effort = "max";
    };
  };

  # Qwen's template accepts the `reasoning_effort` values `xhigh`, `medium` and
  # `low` (there is no `none`). `high` maps to the template's `xhigh`.
  qwenThinking = {
    off = {
      enable_thinking = false;
    };
    low = {
      enable_thinking = true;
      reasoning_effort = "low";
    };
    medium = {
      enable_thinking = true;
      reasoning_effort = "medium";
    };
    high = {
      enable_thinking = true;
      reasoning_effort = "xhigh";
    };
  };

  # The server shares one KV pool per model (unified KV, 4 slots). The pool is
  # usage-proportional: a request only occupies the tokens it actually sends, so a
  # small request is automatically small and a large one reaches the full window.
  # There is deliberately no server-side per-slot cap (`--kv-unified-per-slot`),
  # and llama-swap has no per-alias context either, so a model's context cannot be
  # limited per client. Each request therefore runs at the model's real maximum:
  # DS4 at 320K, Qwen at 1M. Discovery reads those maxima from the server (see
  # `kdn.llm.client.upstreams.brys` below); no tier aliases are used.
  #
  # One opencode subagent per (model, level). The agent's `options` carry that
  # model's `chat_template_kwargs`; the provider model id is the base model id.
  mkAgents =
    {
      prefix,
      modelLabel,
      modelId,
      thinking,
    }:
    lib.listToAttrs (
      map (
        level:
        lib.nameValuePair "${prefix}-${level}" {
          description = "${modelLabel} on brys, thinking ${level}.";
          mode = "subagent";
          model = "brys/${modelId}";
          options.chat_template_kwargs = thinking.${level};
        }
      ) thinkingLevels
    );

  ds4Agents = mkAgents {
    prefix = "ds4";
    modelLabel = "DeepSeek V4 Flash";
    modelId = "deepseek-v4-flash";
    thinking = ds4Thinking;
  };
  qwenAgents = mkAgents {
    prefix = "qwen";
    modelLabel = "Qwen3.8-Flash-Next";
    modelId = "qwen3.8-flash-next";
    thinking = qwenThinking;
  };
  # DS4 low and medium are equivalent: its template ignores `reasoning_effort`
  # except for `max`. DS4 high is `reasoning_effort = "max"`. Qwen high is the
  # template's `xhigh`.
  tierAgents = ds4Agents // qwenAgents;
in
{
  imports = inputs.nix-configs.denLib.imports {
    class = "devenv";
    # `ssh-ca` pulls in `ca-manager`, so this shell holds the `kdn-certs` CLI and the CA DAG.
    # That is the client half of the SSH CA: `kdn-certs ssh login <host>` writes the user
    # certificate this host presents.
    aspects = [
      "llm-client"
      "ssh-ca"
    ];
  };

  # The generic opencode aspect turns opencode on, supplies the default permission
  # skeleton, and provides the `opencode` wrapper. `kdn.llm.client` adds the per-upstream
  # provider, and wires the API key itself from `apiKeyFile`.
  #
  # The slot defaults are neutral now. These two settings keep the behaviour that the old
  # slot defaults gave on this host.
  kdn.opencode.settings.provider.requesty = { };
  # One opencode subagent per (model, thinking level). Each one names a brys
  # provider model and carries that model's `chat_template_kwargs` for the level.
  kdn.opencode.settings.agent = tierAgents;
  kdn.opencode.allowedPaths = [
    "/nix/store/**"
    "~/dev/**"
  ];
  kdn.opencode.authKeys.REQUESTY_API_KEY = "requesty";

  kdn.llm.client.upstreams.brys = {
    enable = true;
    baseURL = "https://brys.priv.nb.net.int.kdn.im/v1";
    # The aspect writes the wrapper environment entry from this file, so no manual
    # `kdn.opencode.wrapper.envFiles` line is needed.
    apiKeyFile = "/run/configs/llms/llama-server/api-keys/default";
    # Only discovery is configured. The model id list, the served context, and the
    # per-model names all come from the server's `/v1/models` (llama-swap publishes
    # each model's context as the top-level `context_length`). There is no
    # hand-written overlay, so every request runs at the model's real maximum
    # context (DS4 320K, Qwen 1M).
    discovery.enable = true;
  };
}

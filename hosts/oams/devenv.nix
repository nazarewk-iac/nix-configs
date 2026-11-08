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
  # limited per client. Each request therefore runs at the model's real maximum
  # (Qwen at 1M). Discovery reads that maximum from the server (see
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

  qwenAgents = mkAgents {
    prefix = "qwen";
    modelLabel = "Qwen3.8-Flash-Next";
    modelId = "qwen3.8-flash-next";
    thinking = qwenThinking;
  };
  # Qwen's `high` is the template's `xhigh`.
  tierAgents = qwenAgents;

  # One opencode subagent per brys purpose alias (chat-std-fast, code-deep-slow,
  # ...), derived from `data/llm.nix` so the client follows the server when an
  # alias moves. A caller that names an intent gets the model the fleet serves for
  # it, with no base-model id in the client. See
  # ../brys/llm-agents.nix and
  # ../../docs/tasks/2026-10/llm-model-expansion/alias-scheme.design.md.
  aliasAgents = import ../brys/llm-agents.nix { inherit lib; };
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
  # These two settings keep the behaviour the old slot defaults gave on this host: the
  # Requesty cloud provider (auth from auth.json, hardcodes no model) and its credential,
  # plus the local brys fleet reached through `kdn.llm.client.upstreams.brys` below.
  kdn.opencode.settings.provider.requesty = { };
  # The subagent set. Two families:
  #   * `tierAgents` — one agent per (base model, thinking level): `qwen-high`,
  #     ... A caller pins a model and a depth explicitly.
  #   * `aliasAgents` — one agent per purpose alias: `chat-std-fast`,
  #     `code-deep-slow`, ... A caller names an intent; the server decides the
  #     model. This is the family to prefer for routine work, so the served
  #     model can move without a client change.
  kdn.opencode.settings.agent = tierAgents // aliasAgents;
  kdn.opencode.allowedPaths = [
    "/nix/store/**"
    "~/dev/**"
  ];
  kdn.opencode.authKeys.REQUESTY_API_KEY = "requesty";

  # The LiteLLM gateway on etra: one entrypoint in front of the whole fleet, with
  # load-balancing and failover across brys and oams. Same discovery model as `brys`;
  # the key is the gateway master key (a sops secret the client reads at runtime).
  kdn.llm.client.upstreams.litellm = {
    enable = true;
    # The gateway is exposed on its own subdomain over HTTPS by etra's Caddy.
    baseURL = "https://litellm.etra.priv.nb.net.int.kdn.im/v1";
    # Non-admin client key (all models), not the master key.
    apiKeyFile = "/run/configs/llms/litellm/client-key";
    discovery.enable = true;
  };

  # On oams itself, keep a direct loopback path to the local llama-swap so this
  # host still works offline (no gateway, no network). The remote `brys` direct
  # endpoint is dropped: off-host traffic goes through the gateway.
  kdn.llm.client.upstreams.oams = {
    enable = true;
    baseURL = "http://127.0.0.1:9530/v1";
    apiKeyFile = "/run/configs/llms/llama-server/api-keys/default";
    discovery.enable = true;
  };
}

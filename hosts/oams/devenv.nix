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
  # The common thinking levels. Every model tier gets one opencode subagent per
  # level, named `<prefix>-<tier>-<level>`, so a caller picks a model, a context
  # budget and a thinking depth in one name.
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

  # The DeepSeek V4 Flash context tiers, on the client side. The server shares
  # one 320K KV pool (unified KV, 4 slots), so a smaller tier costs nothing
  # server-side: the pool is usage-proportional and a small request is
  # automatically small. There is deliberately no server-side per-slot cap
  # (`--kv-unified-per-slot`); the tier only bounds what opencode sends, which is
  # what lets a sub-agent stay cheap.
  #
  # 16K is the smallest useful subagent tier: opencode sends a ~5K-token system
  # prompt plus tool schemas, so an 8K window overflows and the request stalls.
  # Verified 2026-10-06: a 16K subagent read a file and returned the right
  # answer. `output` scales with the tier, so input + output fit the window
  # (16K -> 4K output, 32K+ -> 8K).
  #
  # Every tier points at the same DS4 model. The tier ids must be server aliases
  # of `deepseek-v4-flash` (see hosts/brys/llm.nix): the compat-proxy routes an
  # unknown id to the frontier upstream but does not rewrite it, and
  # llama-server then rejects it with HTTP 400. The aliases add no KV cap and no
  # memory — `parallel 4` shares the one unified pool.
  ds4Contexts = [
    327680 # 320K: the full shared pool
    262144 # 256K
    196608 # 192K
    131072 # 128K
    98304 # 96K
    65536 # 64K
    32768 # 32K
    16384 # 16K: smallest useful subagent tier
  ];
  ds4K = ctx: toString (ctx / 1024);
  ds4TierId = ctx: if ctx == 327680 then "deepseek-v4-flash" else "deepseek-v4-flash-${ds4K ctx}k";

  # The Qwen3.8-Flash-Next context tiers. The 1M tier is the base model id
  # itself; every smaller tier is a server alias `qwen3.8-flash-next-<n>k`
  # (see hosts/brys/llm.nix). Thinking is selected per request
  # (`chat_template_kwargs`), not per alias, so no thinking aliases exist or are
  # needed.
  qwenContexts = [
    1048576 # 1M: the base model id
    262144 # 256K
    131072 # 128K
    65536 # 64K
    32768 # 32K
    16384 # 16K: smallest useful subagent tier
  ];
  qwenTierLabel = ctx: if ctx == 1048576 then "1m" else "${toString (ctx / 1024)}k";
  qwenTierId =
    ctx: if ctx == 1048576 then "qwen3.8-flash-next" else "qwen3.8-flash-next-${qwenTierLabel ctx}";

  # One model entry for a tier. The model is the context tier; the thinking
  # matrix is exposed as `variants` on that model, so the user selects the tier
  # as the model and cycles the variant for the thinking level. The model's own
  # `options` set the default level (`low`); the server also defaults to `low`.
  # `reasoning = true` tells opencode to parse the model's thinking output.
  # `output` scales with the tier so input + output fit the window.
  tierModel =
    {
      modelId,
      tierLabel,
      context,
      thinking,
    }:
    {
      name = "${modelId} (brys, LAN) [${tierLabel}]";
      context = context;
      output = lib.min 8192 (context / 4);
      reasoning = true;
      options.chat_template_kwargs = thinking.low;
      variants = lib.mapAttrs (_: kwargs: { chat_template_kwargs = kwargs; }) thinking;
    };

  ds4Models = lib.listToAttrs (
    map (
      ctx:
      lib.nameValuePair (ds4TierId ctx) (tierModel {
        modelId = "deepseek-v4-flash";
        tierLabel = "${ds4K ctx}K";
        context = ctx;
        thinking = ds4Thinking;
      })
    ) ds4Contexts
  );
  qwenModels = lib.listToAttrs (
    map (
      ctx:
      lib.nameValuePair (qwenTierId ctx) (tierModel {
        modelId = "qwen3.8-flash-next";
        tierLabel = qwenTierLabel ctx;
        context = ctx;
        thinking = qwenThinking;
      })
    ) qwenContexts
  );

  # One opencode subagent per (model, tier, level). The level picks the request
  # body's `chat_template_kwargs`; the model entry itself carries no options.
  mkTierAgents =
    {
      prefix,
      modelLabel,
      tierLabel,
      tierId,
      thinking,
      contexts,
    }:
    lib.listToAttrs (
      lib.concatMap (
        ctx:
        map (
          level:
          lib.nameValuePair "${prefix}-${tierLabel ctx}-${level}" {
            description = "${modelLabel} on brys, ${tierLabel ctx} context budget, thinking ${level}.";
            mode = "subagent";
            model = "brys/${tierId ctx}";
            options.chat_template_kwargs = thinking.${level};
          }
        ) thinkingLevels
      ) contexts
    );

  ds4Agents = mkTierAgents {
    prefix = "ds4";
    modelLabel = "DeepSeek V4 Flash";
    tierLabel = ctx: "${ds4K ctx}k";
    tierId = ds4TierId;
    thinking = ds4Thinking;
    contexts = ds4Contexts;
  };
  qwenAgents = mkTierAgents {
    prefix = "qwen";
    modelLabel = "Qwen3.8-Flash-Next";
    tierLabel = qwenTierLabel;
    tierId = qwenTierId;
    thinking = qwenThinking;
    contexts = qwenContexts;
  };
  # DS4 low and medium are equivalent: its template ignores `reasoning_effort`
  # except for `max`. DS4 high is `reasoning_effort = "max"`. Qwen high is the
  # template's `xhigh`.
  tierAgents = ds4Agents // qwenAgents;
in
{
  imports = inputs.nix-configs.denLib.imports {
    class = "devenv";
    aspects = [ "llm-client" ];
  };

  # The generic opencode aspect turns opencode on, supplies the default permission
  # skeleton, and provides the `opencode` wrapper. `kdn.llm.client` adds the per-upstream
  # provider, and wires the API key itself from `apiKeyFile`.
  #
  # The slot defaults are neutral now. These two settings keep the behaviour that the old
  # slot defaults gave on this host.
  kdn.opencode.settings.provider.requesty = { };
  # Every (model, tier, thinking level) combination as an opencode subagent. Each one
  # names a tiered provider model (see `kdn.llm.client.upstreams.brys.models` below) and
  # carries that model's `chat_template_kwargs` for the level.
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
    # The DS4 and Qwen tiers (generated above) plus the `frontier` alias and the small
    # models.
    models =
      ds4Models
      // qwenModels
      // {
        "frontier" = {
          name = "frontier (deepseek-v4-flash alias, brys) [320K]";
          context = 327680;
          output = 8192;
        };
        # Small models. brys serves these only when booted into the llm-small
        # specialisation; on the default/llm-ds4 boot the compat-proxy falls
        # back to the frontier (DS4). They are kept so a small-only boot is usable
        # without a client change.
        "gpt-oss-120b" = {
          name = "gpt-oss-120b (brys, LAN)";
          context = 65536;
          output = 8192;
        };
        "phi-4" = {
          name = "phi-4 (brys, LAN)";
          context = 16384;
          output = 8192;
        };
        "qwen3-235b" = {
          name = "qwen3-235b (brys, LAN)";
          context = 65536;
          output = 8192;
        };
        "qwen3-30b-a3b" = {
          name = "qwen3-30b-a3b (brys, LAN)";
          context = 65536;
          output = 8192;
        };
        "fast" = {
          name = "fast (qwen3-30b-a3b alias, brys)";
          context = 65536;
          output = 8192;
        };
        "qwen3-coder-next" = {
          name = "qwen3-coder-next (brys, LAN)";
          context = 65536;
          output = 8192;
        };
        "qwen3-next-80b" = {
          name = "qwen3-next-80b (brys, LAN)";
          context = 65536;
          output = 8192;
        };
        "balanced" = {
          name = "balanced (qwen3-next-80b alias, brys)";
          context = 65536;
          output = 8192;
        };
      };
  };
}

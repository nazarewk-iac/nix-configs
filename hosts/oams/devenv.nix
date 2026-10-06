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
  # The same DeepSeek V4 Flash endpoint, tiered by the context window that the
  # client reserves. The server shares one 320K KV pool (unified KV, 4 slots),
  # so a smaller tier costs nothing server-side: the pool is
  # usage-proportional and a small request is automatically small. There is
  # deliberately no server-side per-slot cap (`--kv-unified-per-slot`); the tier
  # only bounds what opencode sends, which is what lets a sub-agent stay cheap.
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
  # One model entry for a tier. `think` adds server-side thinking: opencode sends
  # the `options` object verbatim in the request body, and llama-server turns the
  # thinking block on from `chat_template_kwargs.enable_thinking`.
  ds4Model =
    think: ctx:
    {
      name = "deepseek-v4-flash (brys, LAN) [${ds4K ctx}K${lib.optionalString think ", thinking"}]";
      context = ctx;
      output = lib.min 8192 (ctx / 4);
      reasoning = think;
    }
    // lib.optionalAttrs think {
      options.chat_template_kwargs.enable_thinking = true;
    };
  # One model per (tier, thinking) pair. The thinking id is `<tier-id>-think`, which
  # must be a server alias too (see hosts/brys/llm.nix).
  ds4Models = lib.listToAttrs (
    lib.concatMap (ctx: [
      (lib.nameValuePair (ds4TierId ctx) (ds4Model false ctx))
      (lib.nameValuePair "${ds4TierId ctx}-think" (ds4Model true ctx))
    ]) ds4Contexts
  );
  # One opencode subagent per (tier, thinking) pair, so every combination is
  # directly usable and a caller can pick the cheapest one that fits the task.
  ds4Agents = lib.listToAttrs (
    lib.concatMap (ctx: [
      (lib.nameValuePair "ds4-${ds4K ctx}k" {
        description = "DeepSeek V4 Flash on brys with a ${ds4K ctx}K context budget.";
        mode = "subagent";
        model = "brys/${ds4TierId ctx}";
      })
      (lib.nameValuePair "ds4-${ds4K ctx}k-think" {
        description = "DeepSeek V4 Flash on brys, ${ds4K ctx}K context budget, server-side thinking on.";
        mode = "subagent";
        model = "brys/${ds4TierId ctx}-think";
      })
    ]) ds4Contexts
  );
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
  # The DS4 context tiers, as opencode subagents. Each one names a tiered provider
  # model (see `kdn.llm.client.upstreams.brys.models` below).
  kdn.opencode.settings.agent = ds4Agents;
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
    # The DS4 tiers (generated above) plus the `frontier` alias and the small
    # models.
    models = ds4Models // {
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

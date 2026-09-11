# oams-specific devenv slot instance.
#
# A thin `mkSlots` instance scoped to the oams host, imported by the primary
# `devenv.nix` via `profiles.hostname."oams".module`. It enables opencode (via
# the generic `kdn.opencode` slot) and feeds the required info to
# `kdn.llm.client`, which writes the opencode provider. The `opencode` wrapper
# injects the brys API key. The self-signed cert is trusted system-wide
# on oams via the `kdn.ca.kdn` slot (security.pki). This file is intentionally
# minimal.
#
# Only the host whose hostname is `oams` auto-activates this profile.
{
  pkgs,
  inputs,
  ...
}:
(inputs.nix-configs.mkSlots {
  inherit pkgs;

  # The generic opencode slot turns opencode on, supplies the default
  # permission skeleton, and provides the `opencode` wrapper. The brys API key
  # is injected into that wrapper via wrapper.envFiles. kdn.llm.client adds the
  # per-upstream provider (no per-upstream wrapper).
  kdn.opencode.enable = true;
  kdn.opencode.wrapper.envFiles.KDN_LLM_API_KEY_brys =
    "/run/configs/llms/llama-server/api-keys/default";
  # The slot defaults are neutral now. These three settings keep the behaviour that
  # the old slot defaults gave on this host.
  kdn.opencode.settings.provider.requesty = { };
  kdn.opencode.allowedPaths = [
    "/nix/store/**"
    "~/dev/**"
  ];
  kdn.opencode.authKeys.REQUESTY_API_KEY = "requesty";

  kdn.llm.client.enable = true;
  kdn.llm.client.upstreams.brys = {
    enable = true;
    baseURL = "https://brys.priv.nb.net.int.kdn.im/v1";
    models = {
      "deepseek-v4-flash" = {
        name = "deepseek-v4-flash (brys, LAN) [192K]";
        context = 196608;
        output = 8192;
      };
      "frontier" = {
        name = "frontier (deepseek-v4-flash alias, brys) [192K]";
        context = 196608;
        output = 8192;
      };
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
}).config.devenv

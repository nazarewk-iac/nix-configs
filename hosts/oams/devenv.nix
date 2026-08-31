# oams-specific devenv slot instance.
#
# A thin `mkSlots` instance scoped to the oams host, imported by the primary
# `devenv.nix` via `profiles.hostname."oams".module`. It enables opencode (via
# the generic `kdn.opencode` slot) and feeds the required info to
# `kdn.llm.client`, which writes the opencode provider and ships the wrapper.
# This file is intentionally minimal — just the endpoint details from the shared
# /run/configs/llms mount.
#
# Only the host whose hostname is `oams` auto-activates this profile.
{
  pkgs,
  inputs,
  ...
}:
(inputs.nix-configs.mkSlots {
  inherit pkgs;

  # The generic opencode slot turns opencode on and supplies the default
  # permission skeleton; kdn.llm.client adds the per-upstream providers +
  # wrappers.
  kdn.opencode.enable = true;

  kdn.llm.client.enable = true;
  kdn.llm.client.upstreams.brys = {
    enable = true;
    baseURL = "https://brys.lan.etra.net.int.kdn.im/v1";
    caCertFile = "/run/configs/llms/certs/public.key";
    apiKeyFile = "/run/configs/llms/llama-server/api-keys/default";
    models = {
      "deepseek-v4-flash" = {
        name = "deepseek-v4-flash (brys, LAN)";
        context = 65536;
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
    };
  };
}).config.devenv

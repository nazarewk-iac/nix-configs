# The single boot entry, `specialisation.llms` (see hosts/brys/default.nix). It serves the whole
# fleet from one llama-swap process: both frontier models through the `matrix` engine (a request
# for the other one swaps the resident model, no reboot), plus the surveyed set and the GPU grunt,
# which co-reside on the W6600 by tier. It used to be one of four entries; the others (`llm-ds4`,
# `llm-small`, `llm-qwen`) were removed when llama-swap made a single entry sufficient.
# Combined frontier specialisation for brys.
#
# BOOT-SELECTED ONLY, NEVER ACTIVATED via switch-to-configuration. This is a
# clean top-level (`inheritParentConfig = false`) boot entry that serves BOTH
# frontier models through one router: DeepSeek V4 Flash (320K, DSpark draft) and
# Qwen3.8-Flash-Next (1M ctx, YaRN x4, MTP draft head disabled). The
# primary router runs with `--models-max 1`, so only one model is resident at a
# time and a request for the other swaps it in (~90-120 s reload) with no
# reboot. The default "brys" entry now serves the same pair (see
# hosts/brys/default.nix) but at the default profile's 128K DS4 context and
# without the isolcpus/ARC tuning; this entry keeps the full 320K DS4 and the
# appliance kernel. The common appliance body lives in ./llm-appliance.nix.
#
# Why one router for both: the dedicated ./llm-ds4.nix and ./llm-qwen.nix entries
# each hold one model for the whole box. This entry trades the per-model tuning
# for not having to reboot to switch which frontier answers. The Qwen path is
# identical to ./llm-qwen.nix (shared via ./llm.nix `qwenGpu`/`qwenVulkan`); the
# DS4 path is identical to ./llm-ds4.nix.
{
  lib,
  pkgs,
  kdnConfig,
  ...
}:
let
  # The whole local-LLM serving config, shared with the main brys profile
  # (./llm-config.nix). The appliance passes the full 320K DeepSeek context because it
  # owns the box; the desktop passes 128K because it shares RAM with a browser. That is
  # the only difference.
  llm = import ./llm-config.nix {
    inherit lib pkgs kdnConfig;
    contextSize = 327680;
  };
in
import ./llm-appliance.nix {
  inherit
    lib
    pkgs
    kdnConfig
    llm
    ;
  tag = "llms-frontier";
  banner = ''
    \e[1;33m============================================================\e[0m
    \e[1;31m  COMBINED frontier instance  (brys / llms-frontier)\e[0m
    \e[1;33m============================================================\e[0m
    DS4 + Qwen in one router, models-max 1; a request for either swaps the
    resident model (~90-120 s reload), no reboot.

    DeepSeek V4 Flash @ 320K ctx, DSpark draft, 4 shared slots.
    Qwen3.8-Flash-Next @ 1M ctx (YaRN x4), q8_0 KV, MTP off.
    \e[1;33m============================================================\e[0m
    Login with your usual kdn/SSH credentials. Use the normal host to do
    anything else.
  '';
  # The runtime graphics/ICD config is owned by llm.nix (`llm.gpu`) so the
  # dedicated and combined Qwen specialisations cannot drift.
  extraConfig = llm.gpu;
}

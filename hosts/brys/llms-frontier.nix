# Combined frontier specialisation for brys.
#
# BOOT-SELECTED ONLY, NEVER ACTIVATED via switch-to-configuration. This is a
# clean top-level (`inheritParentConfig = false`) boot entry that serves BOTH
# frontier models through one router: DeepSeek V4 Flash (320K, DSpark draft) and
# Qwen3.8-Flash-Next (1M ctx, YaRN x4, MTP draft head on the W6600 Vulkan). The
# primary router runs with `--models-max 1`, so only one model is resident at a
# time and a request for the other swaps it in (~90-120 s reload) with no
# reboot. The default "brys" entry is unaffected. The common appliance body
# lives in ./llm-appliance.nix.
#
# Why one router for both: the dedicated ./llm-ds4.nix and ./llm-qwen.nix entries
# each hold one model for the whole box. This entry trades the per-model tuning
# for not having to reboot to switch which frontier answers. The Qwen path is
# identical to ./llm-qwen.nix (shared via ./llm.nix `qwenGpu`); the DS4 path is
# identical to ./llm-ds4.nix.
{
  lib,
  pkgs,
  kdnConfig,
  ...
}:
let
  # Shared local-LLM serving config (see ./llm.nix). Both frontier models on the
  # primary router; `cpuPinned = false` for the same llama-cpp 0.4.0
  # prefill-stall reason as the other entries. `qwenGpu = true` owns the W6600
  # Vulkan package/draft/device defaults and exports the runtime graphics
  # config (llm.gpu).
  llm = import ./llm.nix {
    inherit lib pkgs kdnConfig;
    contextSize = 327680;
    cpuPinned = false;
    withFrontier = true;
    withQwen = true;
    withSmall = false;
    qwenContextSize = 1048576;
    qwenGpu = true;
    qwenMtp = true;
    qwenSpecDraftNMax = 5;
    # YaRN x4: 256K native -> 1M. F16 KV (~24 GiB) stays on the CPU.
    qwenRopeScaling = "yarn";
    qwenRopeScale = 4.0;
    qwenRopeFreqBase = 10000000;
    qwenYarnOrigCtx = 262144;
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
    Qwen3.8-Flash-Next @ 1M ctx (YaRN x4), MTP draft head on the W6600.
    \e[1;33m============================================================\e[0m
    Login with your usual kdn/SSH credentials. Use the normal host to do
    anything else.
  '';
  # The runtime graphics/ICD config is owned by llm.nix (`llm.gpu`) so the
  # dedicated and combined Qwen specialisations cannot drift.
  extraConfig = llm.gpu;
}

# Canonical Qwen specialisation for brys.
#
# BOOT-SELECTED ONLY, NEVER ACTIVATED via switch-to-configuration. This is a
# clean top-level (`inheritParentConfig = false`) boot entry that serves the
# Qwen3.8-Flash-Next frontier model with the MTP draft head on the Radeon Pro
# W6600 (Vulkan) and the main model + KV cache on the CPU. The default "brys"
# entry is unaffected. The common appliance body lives in ./llm-appliance.nix.
#
# Why draft-only offload: the benchmark (docs/local-llms.md) shows that moving
# the main model's dense layers to the 8 GB W6600 with the 1M-context KV cache
# pinned to the CPU is far slower (`-ngl 99 -cmoe -nkvo`: 2.0 tok/s decode vs
# 9.1 CPU), because every attention step then crosses PCIe to the CPU-resident
# KV. Offloading only the ~6 GB MTP draft head keeps the main model's weights
# and KV together in RAM and removes the draft's per-step CPU cost: decode rose
# to 10.5 tok/s (+15% over CPU), the only variant that beats the CPU baseline.
{
  lib,
  pkgs,
  kdnConfig,
  ...
}:
let
  # Shared local-LLM serving config, also used by the main brys profile
  # (hosts/brys/default.nix, see ./llm.nix). The Qwen shape: 1M context,
  # YaRN x4, MTP n-max 5, with the Vulkan llama.cpp build and the MTP draft
  # head on the W6600.
  llm = import ./llm.nix {
    inherit lib pkgs kdnConfig;
    withFrontier = false;
    withSmall = false;
    withQwen = true;
    qwenContextSize = 1048576;
    # The W6600 Vulkan path: the v0.6.0 Vulkan build, the MTP draft head on the
    # GPU, and the device pinned to the W6600. `qwenGpu` owns the shared
    # package/draft/device defaults and exports the runtime graphics config
    # (llm.gpu). qwenNGpuLayers stays null, so the main model keeps llama's
    # CPU-only default.
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
  tag = "llm-qwen";
  banner = ''
    \e[1;33m============================================================\e[0m
    \e[1;31m  Qwen-only instance  (brys / llm-qwen)\e[0m
    \e[1;33m============================================================\e[0m
    Booted into the isolated Qwen-serving topology with the MTP draft head
    on the Radeon Pro W6600 (Vulkan); the main model and KV cache stay on
    the CPU.

    Qwen3.8-Flash-Next @ 1M ctx (YaRN x4), F16 KV, single slot, UD-IQ4_XS.
    \e[1;33m============================================================\e[0m
    Login with your usual kdn/SSH credentials. Use the normal host to do
    anything else.
  '';
  # The runtime graphics/ICD config is owned by llm.nix (`llm.gpu`) so the
  # dedicated and combined Qwen specialisations cannot drift.
  extraConfig = llm.gpu;
}

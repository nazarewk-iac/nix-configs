# Qwen GPU-offload specialisation for brys.
#
# BOOT-SELECTED ONLY, NEVER ACTIVATED via switch-to-configuration. This is a
# clean top-level (`inheritParentConfig = false`) boot entry that serves the
# Qwen3.8-Flash-Next frontier model with the MTP draft head on the Radeon Pro
# W6600 (Vulkan) and the main model on the CPU. It mirrors ./llm-qwen.nix apart
# from the Vulkan llama.cpp build, the draft GPU placement and the RADV ICD
# exposure. The default "brys" and the llm-qwen entries are unaffected. The
# common appliance body lives in ./llm-appliance.nix.
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
  # (hosts/brys/default.nix, see ./llm.nix). Same Qwen shape as ./llm-qwen.nix
  # (1M context, YaRN x4, MTP n-max 5), but the llama.cpp build has the Vulkan
  # backend and the MTP draft head runs on the W6600.
  llm = import ./llm.nix {
    inherit lib pkgs kdnConfig;
    withFrontier = false;
    withSmall = false;
    withQwen = true;
    qwenContextSize = 1048576;
    # The Vulkan build: same v0.6.0 source and MTP graph as the CPU-only build,
    # with GGML_VULKAN on.
    llamaPackage = pkgs.kdn.llama-cpp-v0_6_0-vulkan;
    qwenMtp = true;
    qwenSpecDraftNMax = 5;
    # Draft head on the GPU, main model + KV on the CPU. qwenNGpuLayers stays
    # null, so the main model keeps llama's CPU-only default.
    qwenDraftNGpuLayers = 99;
    qwenDevice = "Vulkan0";
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
  tag = "llm-qwen-gpu";
  banner = ''
    \e[1;33m============================================================\e[0m
    \e[1;31m  Qwen GPU-offload instance  (brys / llm-qwen-gpu)\e[0m
    \e[1;33m============================================================\e[0m
    Booted into the isolated Qwen-serving topology with the MTP draft head
    on the Radeon Pro W6600 (Vulkan); the main model and KV cache stay on
    the CPU.

    Qwen3.8-Flash-Next @ 1M ctx (YaRN x4), F16 KV, single slot, UD-IQ4_XS.
    \e[1;33m============================================================\e[0m
    Login with your usual kdn/SSH credentials. Use the normal host to do
    anything else.
  '';
  # Runtime-only bits: expose the Mesa RADV Vulkan ICD to the loader, and pin
  # the llama-cpp process tree to the W6600 (`1002:73e3`) so the 4 GB Lexa
  # (`Vulkan1`) is never selected. The `device = Vulkan0` preset key is the
  # in-process belt to this env-var suspenders.
  extraConfig = {
    hardware.graphics.enable = true;
    hardware.graphics.extraPackages = [ pkgs.mesa ];
    systemd.services.llama-cpp.environment.MESA_VK_DEVICE_SELECT = "1002:73e3!";
  };
}

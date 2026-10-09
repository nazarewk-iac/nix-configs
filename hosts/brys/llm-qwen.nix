# Canonical Qwen specialisation for brys.
#
# BOOT-SELECTED ONLY, NEVER ACTIVATED via switch-to-configuration. This is a
# clean top-level (`inheritParentConfig = false`) boot entry that serves the
# Qwen3.8-Flash-Next frontier model with the MTP draft head and the main model +
# KV cache on the CPU. The default "brys" entry is unaffected. The common
# appliance body lives in ./llm-appliance.nix.
#
# The W6600 is NOT used. The earlier draft-only offload put the ~6 GB MTP draft
# head on the W6600 (decode 10.5 t/s, +15% over CPU), but the W6600 hard-hangs
# under this workload: at ~40.6K tokens of context the amdgpu ring times out and
# the Vulkan context is lost, after which every decode fails with
# `ErrorDeviceLost` and OpenCode gets empty responses. See the note in ./llm.nix.
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
    # The v0.6.0 build (needed for the Qwen MTP graph) with the MTP draft head
    # on the CPU. `qwenGpu = true` selects the v0.6.0 build; `qwenVulkan = false`
    # keeps it off the W6600, which hard-hangs under this workload (see the note
    # in ./llm.nix). qwenNGpuLayers stays null, so the main model keeps llama's
    # CPU-only default.
    qwenGpu = true;
    qwenVulkan = false;
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
    and the main model + KV cache on the CPU (the W6600 is not used).

    Qwen3.8-Flash-Next @ 1M ctx (YaRN x4), F16 KV, 4 slots (unified pool),
    UD-IQ4_XS.
    \e[1;33m============================================================\e[0m
    Login with your usual kdn/SSH credentials. Use the normal host to do
    anything else.
  '';
  # The runtime graphics/ICD config is owned by llm.nix (`llm.gpu`) so the
  # dedicated and combined Qwen specialisations cannot drift.
  extraConfig = llm.gpu;
}

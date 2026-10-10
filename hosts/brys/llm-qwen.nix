# Canonical Qwen specialisation for brys.
#
# BOOT-SELECTED ONLY, NEVER ACTIVATED via switch-to-configuration. This is a
# clean top-level (`inheritParentConfig = false`) boot entry that serves the
# Qwen3.8-Flash-Next frontier model with the main model + KV cache on the CPU
# (MTP speculative decode is disabled; see the `qwenMtp` note below). The default
# "brys" entry is unaffected. The common appliance body lives in
# ./llm-appliance.nix.
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
    # The fork build (needed for the Qwen MTP graph, and the only build with the
    # #26004 checkpoint persistence + the rebased #29738 session-keyed
    # save/restore) with the MTP draft head on the CPU. `qwenGpu = true` selects
    # the v0.6.0 build as the fallback; `llamaPackage` overrides it with the
    # session build. `qwenVulkan = false` keeps it off the W6600, which
    # hard-hangs under this workload (see the note in ./llm.nix). qwenNGpuLayers
    # stays null, so the main model keeps llama's CPU-only default.
    qwenGpu = true;
    qwenVulkan = false;
    llamaPackage = pkgs.kdn.llama-cpp-sessions;
    # MTP speculative decode is OFF. The implementation stays (the `qwenMtp`,
    # `qwenSpecDraftNMax`/`PMin`/`Prio` options and the draft model entry in
    # ./llm.nix) — only this switch flips it. The Qwen MTP draft head accepted
    # only ~0.42 of drafts (mean len 3.11, measured 2026-10-11), so the
    # speculative overhead did not pay for itself. Set true to re-enable.
    qwenMtp = false;
    qwenSpecDraftNMax = 5;
    # YaRN x4: 256K native -> 1M. q8_0 KV halves the 1M pool (~24 -> ~12 GiB),
    # returned to the mmap'd weight working set so decode stops faulting weights
    # from disk (measured 2026-10-10: ~80K major faults/s at 1M F16 KV pinned the
    # box; see docs/local-llms.md). Decode is slightly slower per step but the
    # whole run is far faster because the weights stay resident.
    qwenRopeScaling = "yarn";
    qwenRopeScale = 4.0;
    qwenRopeFreqBase = 10000000;
    qwenYarnOrigCtx = 262144;
    qwenCacheTypeK = "q8_0";
    qwenCacheTypeV = "q8_0";
    # Prompt cache: 8 GiB, down from 16. The disk session store
    # (docs/tasks/2026-10/llm-session-cache-persistence/) now persists whole
    # sessions, so the RAM prompt cache only needs the shared system prompt.
    # It grows on demand, so this is a ceiling, not an allocation.
    qwenCacheRam = 8192;
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
    Booted into the isolated Qwen-serving topology (MTP off) with the main
    model + KV cache on the CPU (the W6600 is not used).

    Qwen3.8-Flash-Next @ 1M ctx (YaRN x4), q8_0 KV, 4 slots (unified pool),
    UD-IQ4_XS.
    \e[1;33m============================================================\e[0m
    Login with your usual kdn/SSH credentials. Use the normal host to do
    anything else.
  '';
  # The runtime graphics/ICD config is owned by llm.nix (`llm.gpu`) so the
  # dedicated and combined Qwen specialisations cannot drift.
  extraConfig = llm.gpu;
}

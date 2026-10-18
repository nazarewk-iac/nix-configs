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
  # Shared local-LLM serving config (see ./llm.nix). Both frontier models on the
  # primary router; `cpuPinned = false` for the same llama-cpp 0.4.0
  # prefill-stall reason as the other entries. `qwenGpu = true` selects the
  # v0.6.0 build; `qwenVulkan = false` keeps the MTP draft head off the W6600,
  # which hard-hangs under this workload (see the note in ./llm.nix).
  llm = import ./llm.nix {
    inherit lib pkgs kdnConfig;
    contextSize = 327680;
    cpuPinned = false;
    withFrontier = true;
    withQwen = true;
    withSmall = false;
    # Colocate the fast GPU grunt beside the two frontier models: `routers.grunt`
    # (:39705) serves Qwen3.5-4B on the W6600, so a `grunt` request never evicts
    # whichever frontier model is resident on the primary router. This also
    # promotes `llm.gpu` (merged as `extraConfig` below) and selects the Vulkan
    # llama.cpp build. See docs/tasks/2026-10/brys-grunt-colocation/.
    withGrunt = true;
    withSwap = true;
    qwenContextSize = 1048576;
    qwenGpu = true;
    qwenVulkan = false;
    # The fork build with #26004 checkpoint persistence + the rebased #29738
    # session-keyed save/restore (packages/llama-cpp `sessions`). It replaces
    # the plain v0.6.0 build for both models on this router.
    #
    # NOTE: `withGrunt = true` above overrides this with the Vulkan no-BLAS
    # build, because the GPU grunt needs Vulkan and the aspect carries ONE
    # `llamaPackage` for every router. The session-cache features therefore have
    # no effect while the grunt is colocated. See the trade-off note in ./llm.nix.
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

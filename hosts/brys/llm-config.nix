# The whole local-LLM serving configuration for brys, in one place.
#
# Two consumers, and they differ in exactly **one** value:
#
#   * the main profile (hosts/brys/default.nix) — a desktop that also serves the fleet;
#   * the `llms` appliance entry (hosts/brys/llms-frontier.nix, booted as
#     `specialisation.llms`) — a dedicated box that reserves cores for throughput.
#
# Everything else is identical on purpose. The fleet is one set of models, one alias map,
# one build and one cache policy; a second copy of those settings is how the two consumers
# drift. The only honest difference is the DeepSeek KV context: 128K on the desktop (it
# shares RAM with a browser) and 320K on the appliance (it owns the box).
#
# `contextSize` is therefore the sole argument. If a second difference ever appears, add it
# here as a named argument **and say why in this header** — a bare extra argument is how
# this file becomes a settings soup.
#
# See ./llm.nix for what each knob does. The measurements behind them are in
# docs/local-llms.md and hosts/brys/performance.md.
{
  lib,
  pkgs,
  kdnConfig,
  # DeepSeek V4 Flash's KV-cache context. 128K on the desktop, 320K on the appliance.
  # With unified KV this is one shared pool, not a per-slot size.
  contextSize,
}:
import ./llm.nix {
  inherit
    lib
    pkgs
    kdnConfig
    contextSize
    ;

  # `cpuPinned = false` is not a preference. On llama-cpp 0.4.0 the `--cpu-range` affinity
  # applies with the wrong scope — decode is pinned but the prompt threadpool is not — and
  # on an `isolcpus` box a pinned server stalls prefill outright (~2k tokens, no timing
  # line ever). The parameter is kept for the ablation record. See ./llm.nix:218.
  cpuPinned = false;

  # Both frontier models, both boot entries.
  withFrontier = true;
  withQwen = true;
  # Small models are NOT served from `routers.small`; the surveyed set covers them.
  withSmall = false;
  # The GPU grunt sits beside the frontier on the W6600, so a `grunt` request never evicts
  # whichever frontier model is resident. This also promotes `llm.gpu` and selects the
  # Vulkan llama.cpp build. See docs/tasks/2026-10/brys-grunt-colocation/.
  withGrunt = true;
  withSurveyed = true;
  # llama-swap, not the old router mode. One process, matrix sets, model swaps instead of
  # reboots. See docs/tasks/2026-10/llama-swap-concurrency/.
  withSwap = true;

  # The fork build with #26004 checkpoint persistence and the rebased #29738 session-keyed
  # save/restore (packages/llama-cpp `sessions`). It replaces the plain v0.6.0 build for
  # both models. `withGrunt` overrides it with the Vulkan no-BLAS build, because the GPU
  # grunt needs Vulkan and the aspect carries ONE package for every router — so the
  # session-cache features are unavailable while the grunt is enabled.
  llamaPackage = pkgs.kdn.llama-cpp-sessions;

  # Qwen3.8-Flash-Next: 1M context through YaRN x4, q8_0 KV, on the CPU. `qwenGpu = true`
  # selects the v0.6.0 build; `qwenVulkan = false` keeps the MTP draft head off the W6600,
  # which hard-hangs under this workload (see the note in ./llm.nix).
  qwenContextSize = 1048576;
  qwenGpu = true;
  qwenVulkan = false;
  qwenMtp = false;
  qwenSpecDraftNMax = 5;
  qwenRopeScaling = "yarn";
  qwenRopeScale = 4.0;
  qwenRopeFreqBase = 10000000;
  qwenYarnOrigCtx = 262144;
  qwenCacheTypeK = "q8_0";
  qwenCacheTypeV = "q8_0";
  qwenCacheRam = 8192;

  # Multimodal (vision): load the Qwen projector (`mmproj-F16.gguf`), so the server accepts
  # image and video input as well as text. There is no separate vision entry; this one
  # switch turns it on, and the projector downloads only when it is true. See
  # docs/tasks/2026-10/qwen-3.8-flash-next-multimodal/.
  qwenVision = true;
}

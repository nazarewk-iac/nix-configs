# Shared LLM serving configuration for brys.
#
# Two consumers share it: the main host (hosts/brys/default.nix), which also runs a
# desktop, and the single appliance entry (hosts/brys/llms-frontier.nix, booted as
# `specialisation.llms`), which gives the box to the models. This file owns that shared
# wiring so the two cannot drift: the slot assignments, the LLM secrets, the leaf-key
# service, the model persistence directory and the ZFS ARC cap all live here.
#
# The consumers differ in these knobs, so all are arguments:
#
#   * `contextSize` — DeepSeek's KV-cache context. The specialisation gets the
#     full 320K; the main profile takes a smaller 128K so the desktop keeps
#     headroom. With unified KV this is the one shared pool, not per slot.
#   * `cpuPinned` — whether DeepSeek's compute threads bind to the isolated
#     cores. Only the specialisations boot with `isolcpus=1-15`, so only they
#     pin. It must stay false on this build: see the note on deepseekPerf.
#   * `withFrontier` — wire the DeepSeek V4 Flash frontier model on the primary
#     router (default true).
#   * `withSmall` — wire the small-model `routers.small` set and its models
#     (default false). A frontier host and a small host are mutually exclusive
#     in practice: DS4 needs the whole box, so the small set is spun out to its
#     own boot specialisation.
#   * `withQwen` — wire the Qwen3.8-Flash-Next model on the primary router
#     (default false). It is a frontier-class model. The default `brys` profile
#     and the `llms-frontier` specialisation serve it beside DeepSeek
#     (`--models-max 1` swaps the resident model); the `llm-qwen` specialisation
#     serves it alone.
#   * `qwenContextSize` — Qwen's KV-cache context (default 131072). The
#     llm-qwen specialisation names it explicitly.
#   * `llamaPackage` — the llama.cpp build that provides `llama-server`
#     (default `pkgs.llama-cpp`, the pinned 0.4.0; `qwenGpu = true` defaults it
#     to the in-repo v0.6.0 Vulkan no-BLAS build instead). An explicit value
#     always wins over the `qwenGpu` default.
#   * `qwenMtp` — use the Qwen model's MTP head for speculative decode
#     (default false). It adds the draft model and the `draft-mtp` spec type.
#     Only the v0.6.0 and Unsloth-fork builds contain the MTP graph.
#
#     DISABLED on brys (2026-10-11). The 2026-10-07 benchmark ran warm at 128K
#     with a 300-token decode and measured acceptance 1.000, so MTP gave +68%
#     decode (5.65 -> 9.5 t/s). At the served long-context config the draft head
#     accepted only ~0.42 of tokens (mean len 3.11, `--spec-draft-n-max 5`,
#     observed over many turns), so the speculation no longer repaid its cost.
#     The implementation stays; only the switch is false. Both Qwen-serving
#     entries set `qwenMtp = false` (hosts/brys/llm-qwen.nix,
#     hosts/brys/llms-frontier.nix). Re-enable by setting it `true` there. A
#     session saved under MTP-on cannot be restored under MTP-off
#     (`state_read_data: incompatible key rotation`); the server logs one error
#     and starts that session fresh.
{
  lib,
  pkgs,
  kdnConfig,
  contextSize ? 196608,
  cpuPinned ? true,
  withFrontier ? true,
  withSmall ? false,
  withQwen ? false,
  # `withGrunt` wires the GPU grunt set (`routers.grunt`, :39705) and its models
  # (default false). It is the fast small co-tenant for the Qwen orchestrator,
  # served on its OWN router so a grunt request never evicts the orchestrator.
  # When true it also promotes the W6600 runtime config below and switches the
  # `llamaPackage` default to the Vulkan build (see the package note). The
  # Qwen-serving entries set it true; the DS4 and small entries leave it false,
  # so their output stays byte-identical.
  withGrunt ? false,
  # `withSurveyed` wires the surveyed grunt set (`routers.surveyed`, :39706) and
  # its models (default false). It registers the successfully-loading GGUF models
  # from the co-residency survey as EVICTABLE low-priority grunts, so a request
  # for any of them never evicts the frontier. It is enabled alongside `withGrunt`
  # on the swap profiles: the GPU grunts need the Vulkan build and `llm.gpu` that
  # `withGrunt` already selects.
  withSurveyed ? false,
  # `qwenGpu` selects the v0.6.0 llama.cpp build, the one that carries the
  # `qwen4exp` MTP graph the Qwen-serving specialisations need for MTP. It does
  # NOT by itself touch the GPU.
  #
  # `qwenVulkan` additionally offloads the MTP draft head to the W6600 over
  # Vulkan, pins the device, and exports the runtime `gpu` config. It defaults
  # to `qwenGpu` for compatibility, but every Qwen specialisation sets it
  # `false`: the W6600 hard-hangs under this workload.
  #
  # Why `qwenVulkan` is off on brys (measured 2026-10-09): at ~40.6K tokens of
  # context the amdgpu compute ring (`comp_1.2.0`) times out; the kernel resets
  # the ring ("device wedged, but recovered through reset"), but the radv Vulkan
  # context is lost, so every following decode fails instantly with
  # `vk::Queue::submit: ErrorDeviceLost`. llama-server sends an error mid-stream
  # and OpenCode closes the turn with an empty assistant message, so the session
  # "stops without answering" until the server is restarted. The GPU draft head
  # was only ~18% faster decode (10.82 vs ~9.1 t/s), so the CPU MTP path is the
  # stable choice. Do not re-enable without a driver/firmware fix.
  #
  # An explicitly-passed `llamaPackage` / `qwenDraftNGpuLayers` / `qwenDevice`
  # still wins over the default.
  qwenGpu ? false,
  qwenVulkan ? qwenGpu,
  qwenContextSize ? 131072,
  llamaPackage ? null,
  qwenMtp ? false,
  # `qwenVision` wires the multimodal (vision) projector (`mmproj-F16.gguf`, ~0.8 GB)
  # onto the Qwen model. The model is `image-text-to-text`, so llama-server accepts
  # image and video input only when the projector is loaded. Default false: a
  # consumer that omits it serves Qwen text-only, and the projector is downloaded
  # and served only when it is true. The main `brys` profile sets it true
  # (hosts/brys/default.nix); the `llm-qwen` and `llms-frontier` boot entries keep
  # the default. See docs/tasks/2026-10/qwen-3.8-flash-next-multimodal/.
  qwenVision ? false,
  # MTP speculative-decode tuning, used only when `qwenMtp` is set. `nMax` is
  # the max draft tokens per step; `pMin`/`prio` are emitted only when non-null
  # so the preset INI keeps llama's own defaults otherwise.
  qwenSpecDraftNMax ? 2,
  qwenSpecDraftPMin ? null,
  qwenSpecDraftPrio ? null,
  qwenRopeScaling ? null,
  qwenRopeScale ? null,
  qwenRopeFreqBase ? null,
  qwenYarnOrigCtx ? null,
  qwenCacheTypeK ? null,
  qwenCacheTypeV ? null,
  qwenCacheRam ? null,
  # GPU-offload knobs for the Qwen model, used by the llm-qwen specialisation
  # for the W6600 MTP draft head. Each stays off/null unless set, so the main
  # brys profile's preset section is byte-identical to before.
  qwenNGpuLayers ? null,
  qwenCpuMoe ? false,
  qwenNoKvOffload ? false,
  qwenDraftNGpuLayers ? null,
  qwenDevice ? null,
  # `withSwap` turns on the llama-swap lifecycle engine on the matrix routing policy: one process
  # owns every model child, the frontier models swap among themselves, and the grunt runs alongside
  # a frontier model. It sets `kdn.llm.local.swap` (see the slot below). Enable it only where the
  # grunt / Qwen sessions build is present, because the matrix sets name the grunt and frontier
  # routers. The default is false, so the DS4 and small entries keep router mode byte-identical.
  withSwap ? false,
  # The build-farm `agent-check` curve (see `kdn-build-farm-agent`). Absolute free memory, in GiB:
  # at or above `fullFreeGiB` brys takes full build capacity; at or below `oneFreeGiB` it takes a
  # single build; in between it scales linearly. A build's own peak is a few GiB whatever the box
  # size, so an absolute reserve is the honest unit. `maxSlots` is the full-capacity `maxconn`.
  buildProbe ? {
    fullFreeGiB = 30;
    oneFreeGiB = 3;
    maxSlots = 12;
  },
}:
let
  # The small-model router sets, split out so a frontier-only host never pulls
  # them in. `small` is the CPU set (:39704); `grunt` is the GPU set (:39705)
  # colocated with the Qwen orchestrator. See hosts/brys/llm-routers.nix.
  routers = import ./llm-routers.nix;
  small = routers.small;
  grunt = routers.grunt;
  surveyed = routers.surveyed;

  # DS4 aliases. `frontier` is the compatibility name an outside client may use
  # for "the strong model". Thinking is selected per request
  # (`chat_template_kwargs`), so no thinking aliases exist. There are deliberately
  # no context-tier aliases: llama-swap cannot bound context per alias and the
  # client discovery-only config runs each request at the model's real maximum.
  ds4Aliases = [
    "frontier"
    "orchestrate-deep-slow-alt"
  ];

  # Qwen aliases. `qwen` is the short name; thinking is per request, so no
  # thinking aliases. Like DS4, no context-tier aliases.
  #
  # `frontier` belongs to DS4 when DS4 is also served (the combined
  # llms-frontier entry); a router rejects two models claiming one alias. The
  # dedicated Qwen entry (no DS4) keeps `frontier`.
  qwenAliases = [
    "qwen"
    "orchestrate-deep-slow"
  ]
  ++ lib.optional (!withFrontier) "frontier";

  # Build and offload defaults. `qwenGpu` picks the v0.6.0 build (CPU-only);
  # `qwenVulkan` swaps in the Vulkan no-BLAS variant and offloads the draft
  # head. An explicitly-passed argument still wins.
  #
  # The no-BLAS build is deliberate: the BLAS backend (`GGML_BLAS=true`)
  # dequantizes a quantized `src0` to F32 and calls `cblas_sgemm`, which stalls
  # small fresh prompts on brys (measured 2026-10-08: a 124-token fresh prefill
  # ran at 1.0 t/s with BLAS against 10.3-17.7 t/s without, a 10-16x stall).
  # The stall is specific to small prompts; 2K prefill is 1.6x and 16K 1.2x
  # faster without BLAS, and 300-token decode is ~30% faster. See
  # packages/llama-cpp/README.md and docs/local-llms.md.
  #
  # When `withGrunt` is set the host serves a GPU grunt beside Qwen, so it needs
  # a build with BOTH the Vulkan backend (for the W6600) AND the session-cache
  # patches (llama.cpp PR #26004 checkpoint persistence + the rebased #29738
  # session-keyed save/restore) that the Qwen entries rely on. One build serves
  # the whole aspect, so the combined `pkgs.kdn.llama-cpp-sessions-vulkan-noblas`
  # is selected: it is built from the same fork source as `llama-cpp-sessions`
  # and adds `vulkan = true; blas = false;`. This removes the earlier trade-off
  # where a GPU grunt dropped Qwen's session cache. `withGrunt` takes precedence
  # over an explicit `llamaPackage` so the combined build is used on every
  # colocated entry; `llama-cpp-sessions-vulkan-noblas` is a superset of both
  # `llama-cpp-sessions` (session cache) and `llama-cpp-v0_6_0-vulkan-noblas`
  # (Vulkan, no BLAS).
  llamaPackage' =
    if withGrunt then
      pkgs.kdn.llama-cpp-sessions-vulkan-noblas
    else if llamaPackage != null then
      llamaPackage
    else if qwenVulkan then
      pkgs.kdn.llama-cpp-v0_6_0-vulkan-noblas
    else if qwenGpu then
      pkgs.kdn.llama-cpp-v0_6_0
    else
      pkgs.llama-cpp;
  qwenDraftNGpuLayers' =
    if qwenDraftNGpuLayers != null then
      qwenDraftNGpuLayers
    else if qwenVulkan then
      99
    else
      null;
  qwenDevice' =
    if qwenDevice != null then
      qwenDevice
    else if qwenVulkan then
      "Vulkan0"
    else
      null;

  # DeepSeek V4 Flash perf.
  #
  # CPU affinity is deliberately NOT set. On llama-cpp 0.4.0 (build 10809) the
  # `--cpu-range`/`--cpu-strict` affinity applies with the wrong scope: decode
  # is pinned but the prompt-processing threadpool is not placed correctly, and
  # on this isolcpus box a pinned server stalls prefill outright (measured: a
  # ~2k-token prompt never emits a timing line with `--cpu-range 1-12`, pinned
  # or not strict). Left unpinned the scheduler places the 12 threads on the
  # isolated cores by itself and prefill runs (~7.5 tok/s over a 2k prompt).
  # `cpuPinned` is kept as a parameter for the ablation record but must stay
  # false. `threads` follows `defaultThreads` (16) unless overridden.
  deepseekPerf = {
    contextSize = contextSize;
    # Thinking is available to clients: `auto` lets the template decide (on for
    # this reasoning model). DS4's template honours only `reasoning_effort =
    # "max"`, so the default `low` is the template's thinking-on with no explicit
    # effort; a caller sets `max` per request via chat_template_kwargs.
    reasoning = "auto";
    reasoningEffort = "low";
    specType = "draft-dspark";
    # DSpark draft depth (--spec-draft-n-max). The DSpark drafter has a trained
    # block size of 5, so llama clamps any larger value to 5. Measured on brys
    # (320K unified KV, warm steady decode): n-max 2 = 5.8 t/s, 3 (the llama
    # default) = 6.5, 4 = 6.5, 5 = 6.8. n-max 5 is the best and the maximum
    # effective value; acceptance falls (0.78 vs 0.88) but the mean accepted
    # length rises (4.82 vs 3.63), so the net decode is about 6% above the
    # default. The Unsloth "3 is the sweet spot, larger is slower" note does not
    # hold on this CPU+DSpark build.
    specDraftNMax = 5;
    # The v0.6.0 build (selected by `qwenGpu`) dropped `--mmap` and the router
    # rejects the `mmap` preset key, so the combined specialisation must omit it
    # for DS4 too. The pinned 0.4.0 build keeps `mmap = on` (its default is mmap,
    # so the served behaviour is unchanged either way).
    mmap = if qwenGpu then null else true;
    # Prefill (prompt processing) on this 284B MoE is bandwidth-bound on the
    # activated expert weights. The llama default ubatch of 512 reuses them
    # over too few tokens; 4096 reuses them across a whole chunk. Measured on
    # brys, warm, cache-miss prompt: ubatch 512 -> 7.2 tok/s prefill, 2048 ->
    # 13.8, 4096 -> 15.8 at 320K (18.4 at 128K). 8192 regressed. batchSize
    # must be >= ubatchSize.
    batchSize = 4096;
    ubatchSize = 4096;
    # Concurrency: two slots share one KV pool (`kvUnified`). With unified KV
    # `ctx-size` is the pool total, not per slot, so the slots do not multiply KV
    # RAM. Two is the deliberate number, not four: this model decodes at ~2.5 tok/s
    # on a ~40 GB/s memory bus, so four concurrent generations split the same
    # bandwidth and each one crawls, while the fourth slot is never used by the
    # harness (one orchestrator, one reviewer). Small GPU models get the high slot
    # counts instead, because their weights sit in VRAM and cost the CPU bus
    # nothing. Raise this only with a measurement from `llm-stats`
    # (docs/tasks/2026-10/llm-metrics-persistence/).
    parallel = 2;
    kvUnified = true;
  }
  // lib.optionalAttrs cpuPinned {
    cpuRange = "1-12";
    cpuStrict = true;
  };

  # Qwen3.8-Flash-Next perf. Sparse MoE (512 experts, 10 active) with hybrid
  # GDN+QSA attention. Only every 4th layer is full attention, so KV is small:
  # ~3 GiB at 128K, F16. Memory-bandwidth-bound like DeepSeek; batch/ubatch
  # reuse the activated expert weights during prefill. Measured on brys:
  # batch/ubatch 4096/4096 raised prefill from 20.1 to 39.9 tok/s on a
  # 3.4k-token prompt. `parallel = 2` with `kvUnified`: the v0.6.0 QSA indexer
  # cache is a side buffer over the attention cells with the same streams and
  # slots (llama-memory-hybrid-idx.h:15), and the MTP draft is per-seq
  # (common/speculative.cpp:1428), so multiple slots are supported. The unified
  # pool makes `ctx-size` the total shared across the slots. Two, for the same
  # reason as DeepSeek above: this is a bandwidth-bound CPU model.
  qwenPerf = {
    contextSize = qwenContextSize;
    # Thinking is available to clients: `auto` lets the template decide, so it is
    # on for this reasoning model, and the default effort is `low`. A caller
    # overrides the level per request via chat_template_kwargs.reasoning_effort.
    reasoning = "auto";
    reasoningEffort = "low";
    batchSize = 4096;
    ubatchSize = 4096;
    parallel = 2;
    kvUnified = true;
    # The v0.6.0 and Unsloth builds dropped `--mmap` (only `--load-mode`
    # remains) and the router rejects the `mmap` preset key. Omit it; the
    # default load mode is mmap, so the served behaviour is unchanged.
    mmap = null;
    # Long-context extension (all null at the native 262144 window). Each is
    # emitted only when non-null, so the preset INI stays clean otherwise.
    ropeScaling = qwenRopeScaling;
    ropeScale = qwenRopeScale;
    ropeFreqBase = qwenRopeFreqBase;
    yarnOrigCtx = qwenYarnOrigCtx;
    cacheTypeK = qwenCacheTypeK;
    cacheTypeV = qwenCacheTypeV;
    cacheRam = qwenCacheRam;
    # Session cache: automatic save/restore keyed by the x-session-id header
    # (llama.cpp PR #29738), plus context checkpoints so an edited or branched
    # follow-up rewinds to a user-turn boundary instead of re-prefilling the
    # whole prompt. checkpointMinStep is `seconds * prefill_tok_s`; 900 is about
    # 30 seconds at ~30 tok/s (measured base-prompt prefill). Deploy and measure
    # before activating.
    #
    # Measured on brys 2026-10-09: the GDN recurrent state is ~112 MiB, and for
    # this hybrid model a checkpoint is the recurrent state only (the attention
    # KV is not stored), so each checkpoint is ~112 MiB in RAM and in the file
    # appendix. 32 checkpoints x 4 slots is at most ~14 GiB, which fits after
    # `qwenCacheRam` was lowered to 16 GiB. See
    # docs/tasks/2026-10/llm-session-cache-persistence/.
    sessionHeaders = "x-session-id";
    sessionMaxSessions = 64;
    ctxCheckpoints = 32;
    checkpointMinStep = 900;
  }
  // lib.optionalAttrs (qwenNGpuLayers != null) {
    nGpuLayers = qwenNGpuLayers;
  }
  // lib.optionalAttrs qwenCpuMoe {
    cpuMoe = true;
  }
  // lib.optionalAttrs qwenNoKvOffload {
    noKvOffload = true;
  }
  // lib.optionalAttrs (qwenDraftNGpuLayers' != null) {
    draftNGpuLayers = qwenDraftNGpuLayers';
  }
  // lib.optionalAttrs (qwenDevice' != null) {
    device = qwenDevice';
  }
  // lib.optionalAttrs qwenMtp {
    specType = "draft-mtp";
    specDraftNMax = qwenSpecDraftNMax;
  }
  // lib.optionalAttrs (qwenSpecDraftPMin != null) {
    specDraftPMin = qwenSpecDraftPMin;
  }
  // lib.optionalAttrs (qwenSpecDraftPrio != null) {
    specDraftPrio = qwenSpecDraftPrio;
  };

  # The DeepSeek V4 Flash frontier model, on the primary router. deepseek-v4-flash
  # is big, multi-shard, frontier quality, and slow to load. download.glob
  # fetches all 4 shards (~104 GB); llama serves shard 00001. Shard 00001 is
  # legitimately small (~5 MB — the split descriptor + mmap header); llama mmaps
  # shards 02-04 for the full weights. The DSpark draft (~10.9 GB) feeds
  # model-draft (spec-type draft-dspark). Aliases: `frontier` (see ds4Aliases
  # above). There are no context tiers: the client runs each request at the
  # model's real maximum.
  frontierModels = lib.optionalAttrs withFrontier {
    deepseek-v4-flash = {
      enable = true;
      hfRepo = "unsloth/DeepSeek-V4-Flash-GGUF";
      hfFile = "UD-IQ3_XXS/DeepSeek-V4-Flash-UD-IQ3_XXS-00001-of-00004.gguf";
      download.glob = "UD-IQ3_XXS/DeepSeek-V4-Flash-UD-IQ3_XXS-*.gguf";
      aliases = ds4Aliases;
      perf = deepseekPerf;
      draft = {
        enable = true;
        hfRepo = "unsloth/DeepSeek-V4-Flash-0731-GGUF";
        hfFile = "dspark-DeepSeek-V4-Flash-0731-Q8_0.gguf";
      };
    };
  };

  # Qwen3.8-Flash-Next, the newest sparse frontier candidate. Unsloth UD-IQ4_XS
  # (~94 GB, 3 shards) keeps the 51B n-gram embedding table inside the weight
  # shards, so the whole tree stays resident (no --lazy-mode). The first shard
  # is a ~11 MB split descriptor; llama-server mmaps shards 02-03 for the
  # weights. Aliases: `qwen`, and `frontier` when DS4 is not also served; see
  # qwenAliases above. There are no context tiers.
  qwenModels = lib.optionalAttrs withQwen {
    "qwen3.8-flash-next" = {
      enable = true;
      hfRepo = "unsloth/Qwen3.8-Flash-Next-GGUF";
      hfFile = "UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf";
      download.glob = "UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-*.gguf";
      download.minBytes = 10000000;
      aliases = qwenAliases;
      perf = qwenPerf;
    }
    // lib.optionalAttrs qwenMtp {
      draft = {
        enable = true;
        hfRepo = "unsloth/Qwen3.8-Flash-Next-GGUF";
        hfFile = "MTP/mtp-Qwen3.8-Flash-Next-Q8_0.gguf";
      };
    }
    // lib.optionalAttrs qwenVision {
      mmproj = {
        enable = true;
        hfRepo = "unsloth/Qwen3.8-Flash-Next-GGUF";
        hfFile = "mmproj-F16.gguf";
      };
    };
  };
in
{
  # The `kdn.llm.local.*` slot assignments. Merge this into the host's own
  # `mkSlots` call: a second `mkSlots` call would collide on the read-only
  # `slots` option that every rendered target declares.
  # The data half of the LLM wiring, consumed by the den `llm` aspect (inclusion
  # is the switch, so there is no `enable`). See the `nixos` attrset below for
  # the host-side half.
  slot = {
    kdn.llm.local = {
      # The host picks the llama.cpp build; the Qwen MTP benchmark swaps it.
      package = llamaPackage';
      # This machine has 16 physical cores. The slot names no thread count now,
      # so this line keeps the `threads` key that the old slot default wrote.
      defaultThreads = 16;
      modelsDir = "/var/lib/kdn/llms/models";
      download.tokenFile = "/run/configs/llms/huggingface/token";
      domain = "brys.lan.etra.net.int.kdn.im";
      certs.certFile = "${kdnConfig.self}/hosts/brys/certs/llm.pub";
      certs.keyFile = "/run/secrets/kdn/brys/llm.key";
      certs.sans = [
        "brys.lan.etra.net.int.kdn.im"
        "brys.lan.drek.net.int.kdn.im"
        "brys.priv.nb.net.int.kdn.im"
      ];
      apiKeyDir = "/run/configs/llms/llama-server/api-keys";
      download.mode = "fast-polite";
      download.xetConcurrency = 8;

      # Disk-backed session cache for the Qwen specialisations. The model opts
      # in with perf.sessionHeaders (see qwenPerf). The directory is persisted
      # under usr/cache (see the nixos block) and pruned to maxBytes /
      # maxAgeMinutes by the slot's kdn-llm-session-prune timer.
      sessionStore = {
        path = "/var/lib/kdn/llms/sessions";
        group = "llama-cpp-sessions";
        maxBytes = 200 * 1024 * 1024 * 1024;
        # No age rule: prune only when the store exceeds maxBytes.
      };

      # Router and model definitions. The small set is included only for a
      # small-only host; a frontier host keeps DS4 alone on the box. The grunt
      # set is included only for a GPU-grunt host (the Qwen-serving entries).
      models =
        (lib.optionalAttrs withSmall small.kdn.llm.local.models)
        // (lib.optionalAttrs withGrunt grunt.kdn.llm.local.models)
        // (lib.optionalAttrs withSurveyed surveyed.kdn.llm.local.models)
        // frontierModels
        // qwenModels;
    }
    // (
      # A single `routers` key: the outer `//` is a shallow merge, so one
      # `routers.<name>` branch per flag would overwrite the previous one. Nest
      # the flags here instead.
      let
        extraRouters =
          (lib.optionalAttrs withSmall { small = small.kdn.llm.local.routers.small; })
          // (lib.optionalAttrs withGrunt { grunt = grunt.kdn.llm.local.routers.grunt; })
          // (lib.optionalAttrs withSurveyed { surveyed = surveyed.kdn.llm.local.routers.surveyed; });
      in
      lib.optionalAttrs (extraRouters != { }) {
        routers = extraRouters;
      }
    )
    // lib.optionalAttrs withSwap {
      swap = {
        enable = true;
        routerEngine = "matrix";
        # Verbose diagnostics window while brys is brought up: llama-swap at
        # debug log level with every stream (proxy/upstream/http) on stdout and
        # `--verbose` on each child, so a failed load explains itself. Turn this
        # back to false once the topology is trusted (see
        # kdn.llm.local.swap.debug).
        debug = true;
        # Bounded co-residence on the 8 GiB W6600: at most one member of a tier at a time, and
        # the tiers may share the card with one frontier model. Footprints are the measured GGUF
        # sizes (docs/tasks/2026-10/llama-swap-concurrency/sets.research.md):
        #   tier 1: 0.50 / 1.19 / 1.24 GiB -> 1.24 GiB worst case
        #   tier 2: 2.00 / 2.09 / 2.00 / 2.89 GiB -> 2.89 GiB worst case
        # Together with KV and compute buffers this stays under the 7.98 GiB the card reports.
        # Bigger GPU models stay out on purpose: one of them wants most of the card.
        # Serialize the GPU. Put EVERY Vulkan0-backed model (grunt + surveyed) into a single
        # co-residence tier, so at most one GPU model is resident at a time beside the CPU
        # frontier. The old two-tier `&` layout let one grunt *and* one surveyed GPU model be
        # resident together, which wedged the 8 GiB W6600 (`vk::Queue::submit: ErrorDeviceLost`,
        # amdgpu ring reset). CPU models are excluded here, so they still co-reside with the
        # frontier in RAM. Frontier ids are excluded because they live in `main` already.
        coResidentTiers =
          let
            allModels =
              (lib.optionalAttrs withSmall small.kdn.llm.local.models)
              // (lib.optionalAttrs withGrunt grunt.kdn.llm.local.models)
              // (lib.optionalAttrs withSurveyed surveyed.kdn.llm.local.models)
              // frontierModels
              // qwenModels;
            frontierIds = builtins.attrNames (frontierModels // qwenModels);
            gpuIds = lib.filter (
              id: ((allModels.${id}.perf or { }).device or "") == "Vulkan0"
            ) (builtins.attrNames allModels);
          in
          [
            (lib.subtractLists frontierIds gpuIds)
          ];
        persistentModels = [
          "deepseek-v4-flash"
          "qwen3.8-flash-next"
        ];
        vulkanDeviceSelect = "1002:73e3!";
      };
    };
  };

  # Runtime graphics/ICD config for the W6600 Vulkan path, exported when
  # `qwenVulkan` OR `withGrunt` is set. `qwenVulkan` alone is off on brys (the
  # W6600 hard-hangs under Qwen's MTP draft workload); `withGrunt` turns the same
  # block on so a GPU grunt can reach the W6600 without enabling Qwen's MTP draft
  # head. A Qwen-serving specialisation merges this into its NixOS config (see
  # hosts/brys/llm-qwen.nix, hosts/brys/llms-frontier.nix, hosts/brys/default.nix):
  # expose the Mesa RADV Vulkan ICD to the loader and pin the llama-cpp process
  # tree to the W6600 (`1002:73e3`) so the 4 GB Lexa (`Vulkan1`) is never
  # selected. The `device = Vulkan0` preset key is the in-process belt to this
  # env-var suspenders.
  gpu = lib.optionalAttrs (qwenVulkan || withGrunt || withSurveyed) {
    hardware.graphics.enable = true;
    hardware.graphics.extraPackages = [ pkgs.mesa ];
    systemd.services.llama-cpp.environment.MESA_VK_DEVICE_SELECT = "1002:73e3!";
  };

  # The NixOS-side LLM configuration. Import this as a module. It owns the
  # secrets, the leaf-key service, the model persistence directory and the ZFS
  # ARC cap.
  nixos = {
    # Keep local LLM models on the persistent usr/data dataset.
    kdn.disks.persist."usr/data".directories = [
      {
        directory = "/var/lib/kdn/llms/models";
        # World-readable so any user (and the llama-cpp DynamicUser) can read
        # the models; the download script keeps files 644 / dirs 755.
        mode = "0755";
      }
    ];

    # Keep the llama-server session cache on the persistent usr/cache dataset.
    # Mode 0770 with the llama-cpp-sessions group: the llama-cpp DynamicUser
    # joins that group (the slot wires it), so the persisted directory stays
    # writable without world access. A session file holds plaintext prompt
    # tokens and KV, so it must not be world-readable.
    kdn.disks.persist."usr/cache".directories = [
      {
        directory = "/var/lib/kdn/llms/sessions";
        mode = "0770";
        group = "llama-cpp-sessions";
      }
    ];

    # --- Observability: per-request stats, durable -----------------------------
    #
    # llama-swap keeps its per-request performance in a ring buffer (25 records,
    # measured), so it survives neither a burst nor a restart. `llm-stats` polls
    # that ring every two seconds and appends one JSONL line per request, then
    # rewrites a Prometheus textfile. It only issues GETs: it never loads, evicts or
    # unloads a model, so it cannot disturb the fleet.
    #
    # /var/lib/llm-stats must survive a boot. brys has a tmpfs root, so an unlisted
    # path is a tmpfs directory and every sample dies at reboot; the `disposable`
    # bucket is rolled back, so it is not a home either. `sys/state` is the right
    # bucket. Mode 0755 because node_exporter (a different user) must read the
    # textfile, and the data is model ids and timings, never request bodies.
    kdn.disks.persist."sys/state".directories = [
      {
        directory = "/var/lib/llm-stats";
        mode = "0755";
      }
      {
        directory = "/var/lib/prometheus2";
        mode = "0750";
        user = "prometheus";
        group = "prometheus";
      }
      # The TPM age identity blob. This is now the ONLY unattended decryptor at boot: the
      # SSH host key is itself a sops secret, so its generator cannot help before the
      # decrypt, and no YubiKey is present. A tmpfs copy here would vanish at reboot and
      # take `sops-install-secrets` and sshd with it. 0700, root-only.
      {
        directory = "/var/lib/sops-tpm";
        mode = "0700";
      }
    ];

    # The container's writable root (`/var/lib/nixos-containers/<name>`): rebuilt
    # data, not state. `sys/cache` is the right bucket, and it keeps the container
    # from writing into a tmpfs root.
    kdn.disks.persist."sys/cache".directories = [
      {
        directory = "/var/lib/nixos-containers";
        mode = "0755";
      }
    ];

    users.groups.llm-stats = { };
    users.users.llm-stats = {
      isSystemUser = true;
      group = "llm-stats";
      description = "llama-swap statistics collector";
    };

    systemd.services.llm-stats = lib.mkIf withSwap {
      description = "Collect llama-swap per-request performance into JSONL";
      wantedBy = [ "multi-user.target" ];
      wants = [ "llama-swap.service" ];
      after = [ "llama-swap.service" ];
      serviceConfig = {
        User = "llm-stats";
        Group = "llm-stats";
        StateDirectory = "llm-stats";
        StateDirectoryMode = "0755";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.kdn.llm-stats}/bin/llm-stats"
          "collect"
          "--state-dir /var/lib/llm-stats"
          "--prom-textfile /var/lib/llm-stats/llamaswap.prom"
          "--interval 2"
        ];
        Restart = "always";
        RestartSec = 5;
        # A collector that can write anywhere is a liability; it needs one directory and a socket.
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      };
    };

    # --- A small Prometheus, confined in a NixOS container ---------------------
    #
    # Deliberately not `kdn.monitoring-prometheus-stack`: that aspect also brings
    # Grafana, a secret key and a Caddy vhost, and this is one scrape target pair on
    # a box that must give its RAM to the models.
    #
    # Prometheus runs in its own NixOS container rather than on the host, because it
    # is the least trusted thing on this box: it parses untrusted text from two HTTP
    # endpoints and writes an unbounded directory. The container gives it its own
    # filesystem, process table and network namespace, so a bug there cannot touch
    # the models, the session cache or the secrets.
    #
    # Network: `privateNetwork = true`, so the container sees only its veth to the
    # host. llama-swap and node_exporter stay bound to 127.0.0.1, so two socat relays
    # expose exactly two ports on the container bridge address and nothing else.
    # This is the confinement pattern to copy: the guest gets a narrow ingress, not
    # a shared host network.
    containers.prometheus = lib.mkIf withSwap {
      autoStart = true;
      restartIfChanged = true;
      privateNetwork = true;
      hostAddress = "10.233.90.1";
      localAddress = "10.233.90.2";
      # The TSDB lives on the host, in the persistent state bucket, and is bind
      # mounted in. Metrics are state, not cache: they must survive a reboot.
      bindMounts."/var/lib/prometheus2" = {
        hostPath = "/var/lib/prometheus2";
        isReadOnly = false;
      };
      config = { pkgs, ... }: {
        # The guest's own firewall, which is a second `policy drop` input chain. Only
        # node_exporter's traffic and the host's scrapes need to reach it; nothing else
        # in the network namespace is exposed. The host reaches the guest for queries and
        # so the acceptance test can ask the guest for its own target health.
        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 9090 ];
        };

        services.prometheus = {
          enable = true;
          listenAddress = "0.0.0.0";
          port = 9090;
          retentionTime = "30d";
          extraFlags = [ "--storage.tsdb.retention.size=2GB" ];
          scrapeConfigs = [
            {
              job_name = "llama-swap";
              scrape_interval = "15s";
              static_configs = [ { targets = [ "10.233.90.1:39700" ]; } ];
            }
            {
              job_name = "node";
              scrape_interval = "30s";
              static_configs = [ { targets = [ "10.233.90.1:9100" ]; } ];
            }
          ];
        };
        # Inside the container the TSDB is a private path; the bind mount makes it
        # the host's persistent directory. Keep the same directory name so a reader
        # of either config sees one path.
        system.stateVersion = "26.05";
        users.users.prometheus.group = "prometheus";
      };
    };

    # The two narrow relays. `bind=` keeps each listener on the container bridge
    # address, so these two ports are reachable from the guest and from nowhere
    # else. This is the pattern to copy for a containerised service: a narrow
    # ingress, never a shared host network.
    systemd.services."llm-metrics-relay-swap" = lib.mkIf withSwap {
      description = "Relay llama-swap /metrics to the prometheus container bridge";
      wantedBy = [ "multi-user.target" ];
      after = [ "llama-swap.service" ];
      wants = [ "llama-swap.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:39700,bind=10.233.90.1,fork,reuseaddr TCP:127.0.0.1:39700";
        Restart = "always";
        RestartSec = 3;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        DynamicUser = true;
      };
    };

    # The build-farm `agent-check` responder. HAProxy on `etra` cannot see llama-swap (39700 is
    # loopback-only) or prometheus (its container is confined), so this host answers a one-line
    # verdict on a port the proxy can reach: `ready` when ample RAM is free, `drain` when a frontier
    # model is resident. `MemAvailable` is the honest signal — `llamaswap_memory_used_bytes` follows
    # host page cache and does not fall when a model unloads (measured 2026-10-30).
    #
    # A frontier residency costs about 14 GiB (measured), so `drain` starts well before the box is
    # starved.
    systemd.services."kdn-build-farm-agent" = lib.mkIf withSwap {
      description = "Answer HAProxy agent-check with the LLM RAM state";
      wantedBy = [ "multi-user.target" ];
      after = [ "prometheus.service" ];
      wants = [ "prometheus.service" ];
      path = [
        pkgs.curl
        pkgs.gawk # MemTotal from /proc/meminfo
        pkgs.gnugrep
        pkgs.coreutils
        pkgs.socat
      ];
      serviceConfig = {
        # `socat` runs one script per agent-check connection and prints its one-word answer. It binds
        # 0.0.0.0 and the firewall restricts it to the LAN and mesh, because HAProxy on `etra` must
        # reach it and the internal bridge address is not routable off-host.
        ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:39701,fork,reuseaddr SYSTEM:${
          pkgs.writeShellApplication {
            name = "kdn-build-farm-agent";
            text = ''
              # The gauge is the second element of `data.result[0].value`.
              # Fail OPEN: a prometheus hiccup must not silently stop every build on the farm, so an
              # unreadable gauge answers `ready`. The hazard it guards (builds competing with a
              # resident model) only exists when the host is genuinely loaded, and then it is readable.
              set +o pipefail +o errexit
              raw=$(curl -sS --max-time 3 "http://10.233.90.2:9090/api/v1/query?query=node_memory_MemAvailable_bytes" 2>/dev/null || true)
              avail=$(printf '%s' "$raw" | sed -E 's/.*,"([0-9.e+]+)"\]\}\].*/\1/' | cut -d. -f1)
              case "$avail" in
                [0-9]*) ;;
                *) printf 'ready\n'; exit 0 ;;
              esac
              # Curve on ABSOLUTE free memory, not a percentage: what matters is whether a build
              # plus the resident model still fits, and a build peak is a few GiB whatever the box
              # size. At or above FULL_GIB free brys takes full capacity; at or below ONE_GIB free it
              # takes a single build; in between it scales linearly. Tunable per host if needed.
              full_gib=${toString buildProbe.fullFreeGiB}
              one_gib=${toString buildProbe.oneFreeGiB}
              max_slots=${toString buildProbe.maxSlots}
              free_gib=$((avail / 1024 / 1024 / 1024))
              if [ "$free_gib" -ge "$full_gib" ]; then
                slots=$max_slots
              elif [ "$free_gib" -le "$one_gib" ]; then
                slots=1
              else
                # Linear between the two anchors: (free - one) / (full - one).
                slots=$(( 1 + (max_slots - 1) * (free_gib - one_gib) / (full_gib - one_gib) ))
              fi
              # The pool uses `balance first`, and the HAProxy manual states `first` "ignores the
              # server weight", so only `maxconn` is reported: it moves the spill point, and since
              # the x86 pool holds brys alone a lower `maxconn` means fewer concurrent builds.
              #
              # `ready` is NOT optional. The manual is explicit: "only the agent may revert its own
              # actions, so if a server is set to DRAIN … the agent must implement the … actions to
              # bring the service into operations again." A bare `maxconn:12` never clears a DRAIN
              # the agent set earlier, so the server would stay drained forever after one busy
              # period. Emitting `ready` every time is the fix; `maxconn` then shapes the curve.
              printf 'ready maxconn:%s\n' "$slots"
            '';
          }
        }/bin/kdn-build-farm-agent";
        Restart = "always";
        RestartSec = 3;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictAddressFamilies = [ "AF_INET" ];
        DynamicUser = true;
      };
    };

    systemd.services."llm-metrics-relay-node" = lib.mkIf withSwap {
      description = "Relay node-exporter metrics to the prometheus container bridge";
      wantedBy = [ "multi-user.target" ];
      after = [ "prometheus-node-exporter.service" ];
      wants = [ "prometheus-node-exporter.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:9100,bind=10.233.90.1,fork,reuseaddr TCP:127.0.0.1:9100";
        Restart = "always";
        RestartSec = 3;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        DynamicUser = true;
      };
    };

    # The nixpkgs container module exposes no `unitConfig`, so the ordering goes on the
    # generated unit directly. `container@prometheus` sorts before `nftables.service`,
    # so without this the guest boots before the firewall rule that lets it reach the
    # relays: the bridge address then answers from the host but not from inside the
    # guest. The interface rule below is the other half of the fix.
    systemd.services."container@prometheus" = lib.mkIf withSwap {
      after = [
        "nftables.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
    };

    # The guest must reach the two relays across the veth. The `nixos-fw` input chain
    # has `policy drop` and trusts only `lo`, `virbr*` and NetBird; a veth is none of
    # them. Open exactly the two relay ports, on that interface only.
    networking.firewall.interfaces."ve-prometheus".allowedTCPPorts = lib.mkIf withSwap [
      9100
      39700
    ];

    services.prometheus.exporters.node = lib.mkIf withSwap {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9100;
      # `textfile` picks up /var/lib/llm-stats/llamaswap.prom; the rest of the
      # default collector set is dropped so the exporter stays small.
      enabledCollectors = [
        "textfile"
      ];
      extraFlags = [ "--collector.textfile.directory=/var/lib/llm-stats" ];
    };

    # Shared /run/configs/llms secrets: HF token and llama-server API keys.
    # Decrypted to their full sops key paths under /run/configs/llms/. Shared
    # with the oams host (same mount point).
    kdn.security.secrets.sops.files."llms" = {
      sopsFile = "${kdnConfig.self}/llms.nonsensitive.sops.yaml";
      basePath = "/run/configs/llms";
      sops.mode = "0444";
    };

    # Raw-decrypt the brys LLM leaf PRIVATE key from hosts/brys/certs/llm.key.sops
    # into /run/secrets (root-only tmpfs) before Caddy starts. Uses the wrapped
    # `sops` (age identity auto-imported from brys' SSH host key). The pub cert
    # is referenced directly from the store (no decryption). Caddy loads the key
    # via LoadCredential (see the llm slot's caddy wiring).
    systemd.services.kdn-llm-leaf-key = {
      description = "Decrypt brys LLM leaf private key into /run/secrets";
      wantedBy = [ "caddy.service" ];
      before = [ "caddy.service" ];
      path = [
        pkgs.sops
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail
        mkdir -p /run/secrets/kdn/brys
        ${pkgs.sops}/bin/sops decrypt --output-type binary \
          ${kdnConfig.self}/hosts/brys/certs/llm.key.sops \
          > /run/secrets/kdn/brys/llm.key
        chmod 0400 /run/secrets/kdn/brys/llm.key
      '';
    };

    # The LLM tuning both consumers share: the ZFS ARC cap (without it the ARC
    # evicts the mmap'd weights and every request re-reads them from disk),
    # `transparent_hugepage=madvise` and `numa_balancing=disable`. See
    # ./llm-tuning-shared.nix for the measured numbers and for why the core
    # reservation stayed out of it.
    imports = [ ./llm-tuning-shared.nix ];
  };
}

# Shared LLM serving configuration for brys.
#
# The main host (hosts/brys/default.nix) and the llm-ds4 boot specialisation
# (hosts/brys/llm-ds4.nix) serve the DeepSeek V4 Flash frontier model through
# the same `kdn.llm.local` slot. The llm-small boot specialisation
# (hosts/brys/llm-small.nix) serves the small-model router instead, with no
# frontier model. The llm-qwen boot specialisation (hosts/brys/llm-qwen.nix)
# serves the Qwen3.8-Flash-Next model alone. This file owns that shared wiring
# so the consumers cannot drift: the slot assignments, the LLM secrets, the
# leaf-key service, the model persistence directory and the ZFS ARC cap all
# live here.
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
}:
let
  # The small-model router set, split out so a frontier-only host never pulls it
  # in. See hosts/brys/llm-routers.nix.
  small = import ./llm-routers.nix;

  # The DS4 client context tiers (hosts/oams/devenv.nix). Every tier id and its
  # `-think` variant must be a server alias of `deepseek-v4-flash`: the
  # compat-proxy routes an unknown id to the frontier upstream but does not
  # rewrite it, and llama-server then rejects the unknown id with HTTP 400. The
  # base tier id is the model name itself, so it needs no alias. Keep this list
  # in step with `ds4Contexts` in hosts/oams/devenv.nix.
  ds4TierSuffixes = [
    "256k"
    "192k"
    "128k"
    "96k"
    "64k"
    "32k"
    "16k"
  ];
  ds4Aliases = [
    "frontier"
  ]
  ++ map (s: "deepseek-v4-flash-${s}") ds4TierSuffixes
  ++ map (s: "deepseek-v4-flash${s}-think") ([ "" ] ++ map (s: "-${s}") ds4TierSuffixes);

  # The Qwen context tiers. Like the DS4 tiers above, every tier id must be a
  # real server alias of `qwen3.8-flash-next` so the compat-proxy can route an
  # unknown tier id to the Qwen upstream without llama-server rejecting it with
  # HTTP 400. The base model id itself is the 1M tier. Thinking is selected per
  # request (chat_template_kwargs), not per alias, so no thinking aliases are
  # needed.
  #
  # `frontier` belongs to DS4 when DS4 is also served (the combined
  # llms-frontier entry); a router rejects two models claiming one alias. The
  # dedicated Qwen entry (no DS4) keeps `frontier`.
  qwenTierSuffixes = [
    "768k"
    "512k"
    "256k"
    "128k"
    "64k"
    "32k"
    "16k"
  ];
  qwenAliases = [
    "qwen"
  ]
  ++ lib.optional (!withFrontier) "frontier"
  ++ map (s: "qwen3.8-flash-next-${s}") qwenTierSuffixes;

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
  llamaPackage' =
    if llamaPackage != null then
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
    # Concurrency: four slots share one KV pool (`kvUnified`). With unified KV
    # `ctx-size` is the pool total, not per slot, so four slots do not multiply
    # KV RAM. A second request no longer queues behind the first request's full
    # prefill. There is deliberately no server-side per-slot cap
    # (`--kv-unified-per-slot`): the shared pool is usage-proportional, so a
    # small request is automatically small, and the client tiers the context
    # instead (see hosts/oams/devenv.nix).
    parallel = 4;
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
  # 3.4k-token prompt. `parallel = 4` with `kvUnified`: the v0.6.0 QSA indexer
  # cache is a side buffer over the attention cells with the same streams and
  # slots (llama-memory-hybrid-idx.h:15), and the MTP draft is per-seq
  # (common/speculative.cpp:1428), so multiple slots are supported. The unified
  # pool makes `ctx-size` the total shared across the four slots.
  qwenPerf = {
    contextSize = qwenContextSize;
    # Thinking is available to clients: `auto` lets the template decide, so it is
    # on for this reasoning model, and the default effort is `low`. A caller
    # overrides the level per request via chat_template_kwargs.reasoning_effort.
    reasoning = "auto";
    reasoningEffort = "low";
    batchSize = 4096;
    ubatchSize = 4096;
    parallel = 4;
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
  # model-draft (spec-type draft-dspark).
  #
  # The `deepseek-v4-flash-<n>k` aliases exist so the client-side context tiers
  # (hosts/oams/devenv.nix) are routable. The compat-proxy only falls back at
  # the routing level; llama-server still validates the model id, so an unknown
  # id is a 400. The tiers must therefore be real server aliases of the one DS4
  # model. They add no KV cap and no extra memory: `--parallel 4` shares the one
  # unified pool regardless of which alias a request names.
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
  # weights. Aliases: `qwen`, the context tiers (`qwen3.8-flash-next-<n>k`), and
  # `frontier` when DS4 is not also served; see qwenAliases above. The base model
  # id is the 1M tier.
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
      # small-only host; a frontier host keeps DS4 alone on the box.
      models = (lib.optionalAttrs withSmall small.kdn.llm.local.models) // frontierModels // qwenModels;
    }
    // lib.optionalAttrs withSmall {
      routers.small = small.kdn.llm.local.routers.small;
    };
  };

  # Runtime graphics/ICD config for the W6600 Vulkan path, exported only when
  # `qwenVulkan` is set (off on brys: the W6600 hard-hangs). A Qwen-serving
  # specialisation merges this into its NixOS config (see hosts/brys/llm-qwen.nix,
  # hosts/brys/llms-frontier.nix): expose the Mesa RADV Vulkan ICD to the loader
  # and pin the llama-cpp process tree to the W6600 (`1002:73e3`) so the 4 GB
  # Lexa (`Vulkan1`) is never selected. The `device = Vulkan0` preset key is the
  # in-process belt to this env-var suspenders.
  gpu = lib.optionalAttrs qwenVulkan {
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

    # Cap the ZFS ARC at 8 GiB. The model GGUFs live on ZFS, so the default ARC
    # (up to ~half of RAM) competes for physical RAM with the page cache that
    # holds the mmap'd ~103 GB DeepSeek weights. Without this cap the kernel
    # evicts the weights to grow the ARC, and every request re-reads them from
    # disk (measured 0.18 tok/s prefill, 6.3M major faults, 271 GB read). With
    # the cap the weights stay resident: RSS ~92 GB, warm generation ~8.5 tok/s.
    # The box needs its RAM for the model, not for cache.
    boot.kernelParams = [ "zfs.zfs_arc_max=8589934592" ];
  };
}

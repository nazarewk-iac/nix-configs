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
#     (default false). It is a frontier-class model, so a host enables it or
#     DeepSeek, not both.
#   * `qwenContextSize` — Qwen's KV-cache context (default 131072). The
#     llm-qwen specialisation names it explicitly.
{
  lib,
  pkgs,
  kdnConfig,
  contextSize ? 196608,
  cpuPinned ? true,
  withFrontier ? true,
  withSmall ? false,
  withQwen ? false,
  qwenContextSize ? 131072,
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
    reasoning = "off";
    specType = "draft-dspark";
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
  # 3.4k-token prompt. `parallel = 1`: the QSA cache is patched for a single
  # slot only; verify before raising it.
  qwenPerf = {
    contextSize = qwenContextSize;
    reasoning = "off";
    batchSize = 4096;
    ubatchSize = 4096;
    parallel = 1;
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
  # weights. Aliases: `qwen` and `frontier` (this model is the frontier of the
  # llm-qwen boot entry).
  qwenModels = lib.optionalAttrs withQwen {
    "qwen3.8-flash-next" = {
      enable = true;
      hfRepo = "unsloth/Qwen3.8-Flash-Next-GGUF";
      hfFile = "UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf";
      download.glob = "UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-*.gguf";
      download.minBytes = 10000000;
      aliases = [
        "qwen"
        "frontier"
      ];
      perf = qwenPerf;
    };
  };
in
{
  # The `kdn.llm.local.*` slot assignments. Merge this into the host's own
  # `mkSlots` call: a second `mkSlots` call would collide on the read-only
  # `slots` option that every rendered target declares.
  slot = {
    kdn.llm.local = {
      enable = true;
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

      # Router and model definitions. The small set is included only for a
      # small-only host; a frontier host keeps DS4 alone on the box.
      models = (lib.optionalAttrs withSmall small.kdn.llm.local.models) // frontierModels // qwenModels;
    }
    // lib.optionalAttrs withSmall {
      routers.small = small.kdn.llm.local.routers.small;
    };
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

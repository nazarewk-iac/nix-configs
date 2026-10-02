# Shared LLM serving configuration for brys.
#
# Both the main host (hosts/brys/default.nix) and the llm-minimal boot
# specialisation (hosts/brys/llm-minimal.nix) serve the same model set through
# the same `kdn.llm.local` slot. This file owns that shared wiring so the two
# consumers cannot drift: the slot assignments, the LLM secrets, the leaf-key
# service, the model persistence directory and the ZFS ARC cap all live here.
#
# The two consumers differ in exactly two knobs, so both are arguments:
#
#   * `contextSize` — DeepSeek's KV-cache context. The specialisation gets the
#     full 192K; the main profile takes a smaller 128K so the desktop keeps
#     headroom.
#   * `cpuPinned` — whether DeepSeek's compute threads bind to the isolated
#     cores. Only the specialisation boots with `isolcpus=1-15`, so only it
#     pins.
{
  lib,
  pkgs,
  kdnConfig,
  contextSize ? 196608,
  cpuPinned ? true,
}:
let
  # DeepSeek V4 Flash perf. The pinned variant matches the specialisation's
  # isolated cores; the unpinned variant lets the scheduler place the threads
  # and falls back to `defaultThreads`.
  deepseekPerf = {
    contextSize = contextSize;
    reasoning = "off";
    specType = "draft-dspark";
  }
  // lib.optionalAttrs cpuPinned {
    cpuRange = "1-12";
    cpuStrict = true;
    threads = 12;
  };
in
{
  # The `kdn.llm.local.*` slot assignments. Merge this into the host's own
  # `mkSlots` call: a second `mkSlots` call would collide on the read-only
  # `slots` option that every rendered target declares.
  slot = {
    kdn.llm.local.enable = true;
    # This machine has 16 physical cores. The slot names no thread count now,
    # so this line keeps the `threads` key that the old slot default wrote.
    kdn.llm.local.defaultThreads = 16;
    kdn.llm.local.modelsDir = "/var/lib/kdn/llms/models";
    kdn.llm.local.download.tokenFile = "/run/configs/llms/huggingface/token";
    kdn.llm.local.domain = "brys.lan.etra.net.int.kdn.im";
    kdn.llm.local.certs.certFile = "${kdnConfig.self}/hosts/brys/certs/llm.pub";
    kdn.llm.local.certs.keyFile = "/run/secrets/kdn/brys/llm.key";
    kdn.llm.local.certs.sans = [
      "brys.lan.etra.net.int.kdn.im"
      "brys.lan.drek.net.int.kdn.im"
      "brys.priv.nb.net.int.kdn.im"
    ];
    kdn.llm.local.apiKeyDir = "/run/configs/llms/llama-server/api-keys";
    kdn.llm.local.download.mode = "fast-polite";
    kdn.llm.local.download.xetConcurrency = 8;
    # Second router on :39704 holds the freely-swapping small set. It is a SET
    # router: `modelsMax 2` keeps a pair of confirmed-coexistable small models
    # resident together, swapping as a unit against DS4. DS4 on the primary
    # :39703 stays alone (`models-max 1`).
    kdn.llm.local.routers.small = {
      enable = true;
      port = 39704;
      threads = 8;
      modelsMax = 2;
      apiKeyDir = "/run/configs/llms/llama-server/api-keys";
    };
    kdn.llm.local.models = {
      # deepseek-v4-flash: big, multi-shard, frontier quality. Slow to load.
      # download.glob fetches all 4 shards (~104 GB); llama serves shard 00001.
      # Shard 00001 is legitimately small (~5 MB — it is the split descriptor +
      # mmap header); llama mmaps shards 02-04 for the full weights. The DSpark
      # draft (~10.9 GB) feeds model-draft (spec-type draft-dspark).
      deepseek-v4-flash = {
        enable = true;
        hfRepo = "unsloth/DeepSeek-V4-Flash-GGUF";
        hfFile = "UD-IQ3_XXS/DeepSeek-V4-Flash-UD-IQ3_XXS-00001-of-00004.gguf";
        download.glob = "UD-IQ3_XXS/DeepSeek-V4-Flash-UD-IQ3_XXS-*.gguf";
        aliases = [ "frontier" ];
        perf = deepseekPerf;
        draft = {
          enable = true;
          hfRepo = "unsloth/DeepSeek-V4-Flash-0731-GGUF";
          hfFile = "dspark-DeepSeek-V4-Flash-0731-Q8_0.gguf";
        };
      };
      qwen3-30b-a3b = {
        enable = true;
        hfRepo = "Qwen/Qwen3-30B-A3B-GGUF";
        hfFile = "Qwen3-30B-A3B-Q4_K_M.gguf";
        aliases = [ "fast" ];
        mainRouter = "small";
        perf.contextSize = 131072;
      };
      qwen3-next-80b = {
        enable = true;
        hfRepo = "unsloth/Qwen3-Next-80B-A3B-Instruct-GGUF";
        hfFile = "Qwen3-Next-80B-A3B-Instruct-Q4_K_M.gguf";
        aliases = [ "balanced" ];
        mainRouter = "small";
        perf.contextSize = 131072;
      };
      phi-4 = {
        enable = true;
        hfRepo = "microsoft/phi-4-gguf";
        hfFile = "phi-4-Q4_K.gguf";
        mainRouter = "small";
        perf.contextSize = 16384;
      };
      qwen3-coder-next = {
        enable = true;
        hfRepo = "Qwen/Qwen3-Coder-Next-GGUF";
        hfFile = "Qwen3-Coder-Next-Q4_K_M/Qwen3-Coder-Next-Q4_K_M-00001-of-00004.gguf";
        download.glob = "Qwen3-Coder-Next-Q4_K_M/Qwen3-Coder-Next-Q4_K_M-*.gguf";
        mainRouter = "small";
        perf.contextSize = 131072;
      };
      qwen3-235b = {
        enable = true;
        hfRepo = "mradermacher/Qwen3-235B-A22B-i1-GGUF";
        hfFile = "Qwen3-235B-A22B.i1-IQ2_M.gguf.part1of2";
        download.glob = "Qwen3-235B-A22B.i1-IQ2_M.gguf.part*";
        mainRouter = "small";
        perf.contextSize = 65536;
      };
      gpt-oss-120b = {
        enable = true;
        hfRepo = "bartowski/openai_gpt-oss-120b-GGUF";
        hfFile = "openai_gpt-oss-120b-Q4_K_M/openai_gpt-oss-120b-Q4_K_M-00001-of-00002.gguf";
        download.glob = "openai_gpt-oss-120b-Q4_K_M/openai_gpt-oss-120b-Q4_K_M-*.gguf";
        mainRouter = "small";
      };
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

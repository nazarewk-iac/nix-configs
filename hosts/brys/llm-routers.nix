# Small-model router definitions for brys.
#
# Two model sets live here, one per co-tenant path:
#
#   * `small` — the CPU set on :39704. It is a SET router: `modelsMax 2` keeps a
#     pair of confirmed-coexistable small models resident together. It is spun
#     out of the frontier hosts: ./llm.nix imports it only when `withSmall =
#     true`, and only the llm-small boot specialisation sets that (see
#     hosts/brys/llm-small.nix). The llm-ds4 entry and the main brys profile
#     serve DS4 alone, so the small set never competes with DS4's ~101 GB of
#     mmap'd weights for RAM. This set is unchanged by the grunt work.
#
#   * `grunt` — the GPU set on :39705. ./llm.nix imports it only when `withGrunt
#     = true`, and only the Qwen-serving entries set that (hosts/brys/llm-qwen.nix,
#     hosts/brys/llms-frontier.nix, hosts/brys/default.nix). The grunt runs on
#     its OWN router with `modelsMax 1`, so a grunt request never evicts the
#     orchestrator, and its weights live in the W6600's VRAM (Vulkan0), so it
#     uses none of the ~40 GB/s CPU memory bandwidth the orchestrator needs. See
#     docs/tasks/2026-10/brys-grunt-colocation/.
#
# Each value is a partial `kdn.llm.local` attrset, so a consumer merges the one
# it wants into its slot. A `small` host and a `grunt` host are different boot
# entries and a host never imports both.
{
  # The `small` CPU set (unchanged). It is the exact attrset this file returned
  # before; wrapping it under `small` keeps every existing consumer byte-identical.
  small = {
    kdn.llm.local.routers.small = {
      enable = true;
      port = 39704;
      threads = 8;
      modelsMax = 2;
      apiKeyDir = "/run/configs/llms/llama-server/api-keys";
    };

    kdn.llm.local.models = {
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

  # The `grunt` GPU set. One router on its own port with one resident model, so a
  # grunt request reaches it without touching the orchestrator on the primary
  # router. The model runs fully on the W6600 (`nGpuLayers = 99`, `device =
  # "Vulkan0"`), 16K context, a single slot, no speculative decoding — the shape
  # the 2026-10-18 measurement supports (Qwen3.5-4B Q4_K_M, 62 tok/s decode /
  # 1073 tok/s prefill on the W6600).
  #
  # The model id is the server alias `grunt`: the compat-proxy routes an unknown
  # model id to the frontier, so a client names `grunt` (or `qwen3.5-4b`) to
  # reach this router and anything else to stay on the orchestrator.
  grunt = {
    kdn.llm.local.routers.grunt = {
      enable = true;
      port = 39705;
      threads = 8;
      modelsMax = 1;
      apiKeyDir = "/run/configs/llms/llama-server/api-keys";
    };

    kdn.llm.local.models."qwen3.5-4b" = {
      enable = true;
      hfRepo = "unsloth/Qwen3.5-4B-GGUF";
      hfFile = "Qwen3.5-4B-Q4_K_M.gguf";
      mainRouter = "grunt";
      aliases = [ "grunt" ];
      perf = {
        contextSize = 16384;
        nGpuLayers = 99;
        device = "Vulkan0";
        parallel = 1;
      };
    };

    # The quality option: Qwen3.5-9B on the same router (37 tok/s decode / 594
    # tok/s prefill on the W6600, the highest-quality grunt that still fits the
    # 8 GB card at 16K context). DISABLED by default: it is a manual upgrade for
    # a task where the 4B is not good enough. Because the router runs `modelsMax
    # 1`, enabling both models means a request for one evicts the other (~the
    # weights reload from disk), which is acceptable for a grunt but not the
    # default. Set `enable = true` here to serve the 9B instead of, or beside,
    # the 4B.
    kdn.llm.local.models."qwen3.5-9b" = {
      enable = false;
      hfRepo = "unsloth/Qwen3.5-9B-GGUF";
      hfFile = "Qwen3.5-9B-Q4_K_M.gguf";
      mainRouter = "grunt";
      perf = {
        contextSize = 16384;
        nGpuLayers = 99;
        device = "Vulkan0";
        parallel = 1;
      };
    };
  };
}

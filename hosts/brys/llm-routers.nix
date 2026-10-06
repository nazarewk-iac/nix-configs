# Small-model router definitions for brys.
#
# The router on :39704 holds the freely-swapping small model set. It is a SET
# router: `modelsMax 2` keeps a pair of confirmed-coexistable small models
# resident together.
#
# The small set is spun out of the frontier hosts: it is imported by ./llm.nix
# only when `withSmall = true`, and only the llm-small boot specialisation sets
# that (see hosts/brys/llm-small.nix). The llm-minimal entry and the main brys
# profile serve DS4 alone, so the small set never competes with DS4's ~101 GB of
# mmap'd weights for RAM.
{
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
}

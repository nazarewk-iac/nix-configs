# The single source of truth for the LLM fleet.
#
# ## What lives here
#
# One entry per SERVED MODEL, plus the endpoint it is reached through. Every consumer derives
# from this file and none of them repeats a model id, an alias or a context size:
#
#   * the server        `hosts/brys/llm-routers.nix` reads `aliases`, `contextSize`, `gpu`, and the
#                       per-model serve flags (`stats`), so brys stops declaring them itself.
#   * the Pi client     `lib/llm.nix` renders `models.json` from `contextSize` + `pi.*`.
#   * the OpenCode      `hosts/brys/llm-agents.nix` builds one sub-agent per purpose alias.
#     client
#
# ## Pure data
#
# No imports, no `pkgs`, no host facts beyond the endpoint. An adopter replaces this file with
# their own fleet and every consumer follows.
#
# ## The per-tool sub-config
#
# A client sometimes needs more than the served size: Pi needs a client-side context budget and
# an output cap. Those live under `<model>.pi`, and under `.opencode` when a tool needs its own
# view. A missing sub-config means "use the tool's global default" (`pi.defaults` below).
#
# ## Deliberately NOT here
#
# Server runtime knobs that are not part of a model's identity: threads, flash-attn, device pin,
# chat-template fallbacks, slot counts. Those stay in `hosts/brys/llm-routers.nix`, because they
# describe how THIS host serves a model, not what the model is.
let
  # `K` is 1024, so a size reads like the number a human would say: `384 * K`, `32 * K`. Every
  # context and output value in this file uses it. It is a `let` binding because this file is
  # data plus this one helper, not a module.
  K = 1024;
in
{
  # ---------------------------------------------------------------- endpoints
  # The client-facing base URL and the API dialect. `apiKey` is a runtime command reference, so no
  # secret is stored here.
  endpoints = {
    brys = {
      baseUrl = "https://brys.priv.nb.net.int.kdn.im/v1";
      api = "openai-completions";
      apiKey = "!cat /run/configs/llms/llama-server/api-keys/default";
    };
  };

  # ---------------------------------------------------------------- client-wide defaults
  #
  # What the Pi client uses when a model has no `pi` sub-config of its own.
  #
  # `contextWindow` is a BUDGET, not the served size: a 1M model is cheap to request and
  # expensive to hold in RAM, so a session stops at 384k by default. `maxTokens` is an explicit
  # per-model number below; the fallback here is only for a model that sets none.
  pi = {
    defaults = {
      contextWindow = 384 * K;
      maxTokens = 4 * K;
    };
    # Extra label-only aliases for the frontier, so a caller picks a context budget without a
    # config edit. Each is the SAME server model with a different client-side window.
    aliases = {
      "128k" = 128 * K;
      "256k" = 256 * K;
      "long" = 512 * K;
      "longest" = 1024 * K;
    };
  };

  # ---------------------------------------------------------------- models
  #
  # `contextSize` is what llama-server serves. `gpu` is full W6600 offload. `vision` means a
  # multimodal projector is attached. `stats` are serve flags the router passes through.
  models = {
    # ---- frontier (CPU, very large context)
    "qwen3.8-flash-next" = {
      aliases = [
        "qwen"
        "orchestrate-deep-slow"
      ];
      contextSize = 1024 * K;  # 1M
      gpu = false;
      # The frontier is the one model worth a real client budget: 384k of the served 1M.
      pi = {
        contextWindow = 384 * K;
        maxTokens = 32 * K;
      };
    };
    "deepseek-v4-flash" = {
      aliases = [
        "frontier"
        "orchestrate-deep-slow-alt"
      ];
      contextSize = 128 * K;
      gpu = false;
      pi.maxTokens = 16 * K;
    };

    # ---- survey set: CPU, mid context
    "qwen3-30b-a3b" = {
      aliases = [ "fast" ];
      contextSize = 128 * K;
      gpu = false;
    };
    "qwen3-next-80b" = {
      aliases = [ "balanced" ];
      contextSize = 128 * K;
      gpu = false;
    };
    "qwen3.8-27b" = {
      aliases = [
        "chat-deep-slow"
        "code-deep-slow"
        "vision-deep-slow"
        "reason-deep-slow"
        "tools-deep-slow"
      ];
      contextSize = 32 * K;
      gpu = false;
      vision = true;
      pi.maxTokens = 8 * K;
    };
    "lfm2.5-24b-a2b" = {
      aliases = [
        "chat-std-fast"
        "tools-std-fast"
      ];
      contextSize = 32 * K;
      gpu = false;
    };
    "mellum-2.1-12b-a2.5b-thinking" = {
      aliases = [
        "reason-quick-fast"
        "code-std-fast-alt"
      ];
      contextSize = 32 * K;
      gpu = false;
    };
    "nemotron-3-nano-30b-a3b" = {
      aliases = [
        "reason-std-fast"
        "chat-std-mid-long"
      ];
      contextSize = 32 * K;
      gpu = false;
    };
    "north-mini-code-1.0" = {
      aliases = [
        "code-std-fast"
        "code-std-fast-moe"
      ];
      contextSize = 32 * K;
      gpu = false;
    };
    "qwen3.5-35b-a3b" = {
      aliases = [ "chat-std-mid" ];
      contextSize = 8 * K;
      gpu = false;
    };
    "qwen3-vl-8b-instruct" = {
      aliases = [ "vision-quick-fast" ];
      contextSize = 32 * K;
      gpu = false;
      vision = true;
    };
    "qwen3-vl-30b-a3b" = {
      aliases = [
        "vision-std-fast"
        "vision-std-fast-moe"
      ];
      contextSize = 32 * K;
      gpu = false;
      vision = true;
    };
    "qwen3-omni-30b-a3b" = {
      aliases = [ "audio-std-mid" ];
      contextSize = 32 * K;
      gpu = false;
      vision = true;
    };
    "ornith-1.5-35b-a3b" = {
      aliases = [ "vision-std-fast-alt" ];
      contextSize = 32 * K;
      gpu = false;
      vision = true;
    };
    "qwen3-embedding-4b" = {
      aliases = [ "embed-std-fast" ];
      contextSize = 8 * K;
      gpu = false;
    };
    "qwen3-reranker-4b" = {
      aliases = [ "rank-std-fast" ];
      contextSize = 8 * K;
      gpu = false;
    };

    # ---- small GPU models
    "qwen3.5-0.8b" = {
      aliases = [ "tiny-dumb-fast" ];
      contextSize = 16 * K;
      gpu = true;
      stats.parallel = 4;
    };
    "qwen3.5-2b" = {
      aliases = [ "tiny-dumb-fast-alt" ];
      contextSize = 16 * K;
      gpu = true;
      stats.parallel = 4;
    };
    "qwen3.5-4b" = {
      aliases = [
        "grunt"
        "chat-dumb-fast"
        "code-quick-fast"
        "tiny-quick-fast"
      ];
      contextSize = 16 * K;
      gpu = true;
    };
    "tmax-2b" = {
      contextSize = 16 * K;
      gpu = true;
      stats.parallel = 4;
    };
    "granite-4.2-3b" = {
      aliases = [
        "tools-dumb-fast"
        "chat-dumb-fast-alt"
      ];
      contextSize = 16 * K;
      gpu = true;
    };
    "ministral-3-3b-instruct" = {
      contextSize = 16 * K;
      gpu = true;
    };
    "ministral-3-3b-reasoning" = {
      aliases = [ "reason-quick-fast-alt" ];
      contextSize = 16 * K;
      gpu = true;
    };
    "gemma-4-e2b" = {
      contextSize = 16 * K;
      gpu = true;
    };
    "olmo-3-7b-instruct" = {
      contextSize = 16 * K;
      gpu = true;
    };
    "gemma-4-e4b" = {
      contextSize = 16 * K;
      gpu = true;
    };
    "granite-4.2-8b" = {
      aliases = [ "tools-std-fast-alt" ];
      contextSize = 16 * K;
      gpu = true;
    };
    "ministral-3-8b-instruct" = {
      contextSize = 16 * K;
      gpu = true;
    };
    "ministral-3-8b-reasoning" = {
      contextSize = 16 * K;
      gpu = true;
    };
    "tmax-9b" = {
      contextSize = 16 * K;
      gpu = true;
    };
    "mimo-v2.6-qwen-9b" = {
      contextSize = 16 * K;
      gpu = true;
    };

    # ---- CPU variants of the smallest, reachable by a `-cpu` id
    "qwen3.5-0.8b-cpu" = {
      source = "qwen3.5-0.8b";
      contextSize = 8 * K;
      gpu = false;
    };
    "qwen3.5-2b-cpu" = {
      source = "qwen3.5-2b";
      contextSize = 8 * K;
      gpu = false;
    };
    "tmax-2b-cpu" = {
      source = "tmax-2b";
      contextSize = 8 * K;
      gpu = false;
    };

    # ---- CPU models with a small serve context
    "gemma-4-12b" = {
      contextSize = 16 * K;
      gpu = false;
    };
    "gemma-4-26b-a4b" = {
      contextSize = 8 * K;
      gpu = false;
    };
    "gemma-4-31b" = {
      contextSize = 8 * K;
      gpu = false;
    };
    "granite-4.2-30b" = {
      contextSize = 8 * K;
      gpu = false;
    };
    "glm-4.7-flash" = {
      contextSize = 8 * K;
      gpu = false;
    };
    "olmo-3.1-32b" = {
      contextSize = 8 * K;
      gpu = false;
    };
    "qwen3.6-27b" = {
      contextSize = 8 * K;
      gpu = false;
    };
    "qwen3.6-35b-a3b" = {
      contextSize = 8 * K;
      gpu = false;
    };
    "nemotron-3.5-lightning-30b" = {
      contextSize = 8 * K;
      gpu = false;
    };
    "seed-oss-36b" = {
      contextSize = 8 * K;
      gpu = false;
    };
  };
}

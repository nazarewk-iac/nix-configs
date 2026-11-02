# The single source of truth for the LLM fleet.
#
# ## What lives here
#
# One entry per SERVED MODEL, plus the endpoint it is reached through and the
# cross-model serving data for each host. Every consumer derives from this file
# and none of them repeats a model id, an alias or a context size:
#
#   * the server   `hosts/brys/llm.nix` projects `mkServerModels data "brys" <profile>`
#                  into `kdn.llm.local`: what to load, which router, what per-host perf.
#   * the client   `lib/llm.nix` renders Pi's `models.json` and the orchestrator catalog
#                  from each model's identity (`contextSize`, `pi.*`, `capabilities`, `vision`).
#   * the member   `lib/llm.nix`'s `mkMemberView data "<host>"` gives a host the endpoint and
#                  the alias-to-model map, with no serving plumbing (no file, no perf, no port).
#
# See docs/tasks/2026-11/fleet-llm-data-model/design.md for the shape and the review record.
#
# ## Pure data
#
# No imports, no `pkgs`, no host-specific store paths. A host supplies the few
# values that need `pkgs`/`self` (the package, the TLS cert path) when it builds
# `kdn.llm.local`; everything model-shaped is here. An adopter replaces this file
# with their own fleet and every consumer follows.
#
# ## Identity vs serving
#
# A model's IDENTITY is the same on every host: `aliases`, `contextSize` (native),
# `capabilities`, `pi`, `vision`, `gpu`, `source`. Its SERVING data is per host:
# `hosts.<host>.set` (the router), `hosts.<host>.servedContext` (the window this
# host serves), `hosts.<host>.common` (file, download, mmproj, draft, perf), and an
# optional `hosts.<host>.profiles.<profile>` delta (a boot profile that differs).
#
# ## Context values
#
# `contextSize`        (identity)            the NATIVE trained window.
# `servedContext`      (model x host)        the window this host serves.
# `profiles.<p>.servedContext` (x profile)   the window a specific boot profile serves.
# Precedence: profile ?? host ?? native.
let
  # `K` is 1024, so a size reads like the number a human would say: `384 * K`, `32 * K`.
  K = 1024;
in
{
  # ---------------------------------------------------------------- endpoints
  endpoints = {
    brys = {
      baseUrl = "https://brys.priv.nb.net.int.kdn.im/v1";
      api = "openai-completions";
      apiKey = "!cat /run/configs/llms/llama-server/api-keys/default";
    };
  };

  # ---------------------------------------------------------------- client-wide defaults
  pi = {
    defaults = {
      contextWindow = 384 * K;
      maxTokens = 4 * K;
    };
    # Extra label-only aliases for the frontier, so a caller picks a context budget
    # without a config edit. Each is the SAME server model with a different window.
    aliases = {
      "128k" = 128 * K;
      "256k" = 256 * K;
      "long" = 512 * K;
      "longest" = 1024 * K;
    };
  };

  # ---------------------------------------------------------------- servers
  #
  # Cross-model serving data for a host. Pure: the host adds `package` (mapped
  # to a `pkgs` attr) and the TLS cert path (`self`), which need the build inputs.
  servers = {
    brys = {
      # A named key; the host maps it to `pkgs.kdn.<key>`. `withGrunt` on brys selects
      # the Vulkan no-BLAS build with the session-cache patches.
      package = "llama-cpp-sessions-vulkan-noblas";
      defaultThreads = 16;
      modelsDir = "/var/lib/kdn/llms/models";
      download = {
        tokenFile = "/run/configs/llms/huggingface/token";
        mode = "fast-polite";
        xetConcurrency = 8;
      };
      apiKeyDir = "/run/configs/llms/llama-server/api-keys";

      # Disk-backed session cache for the Qwen specialisations. A model opts in with
      # `perf.sessionHeaders`. Persisted under usr/cache and pruned to maxBytes.
      sessionStore = {
        path = "/var/lib/kdn/llms/sessions";
        group = "llama-cpp-sessions";
        maxBytes = 200 * 1024 * 1024 * 1024;
      };

      # Extra routers on this host. `main` is llama-swap's primary router (the
      # primary `services.llama-cpp` server), so it is not listed here; it is
      # selected by `set = "main"` below. These two are extra routers.
      routers = {
        grunt = {
          enable = true;
          port = 39705;
          threads = 8;
          modelsMax = 1;
          apiKeyDir = "/run/configs/llms/llama-server/api-keys";
        };
        surveyed = {
          enable = true;
          port = 39706;
          threads = 8;
          modelsMax = 1;
          apiKeyDir = "/run/configs/llms/llama-server/api-keys";
        };
      };

      # Cross-model serving policy, the resolved value. `coResidentTiers` is the
      # resolved list of co-residence groups: one tier of mutually-exclusive GPU
      # (Vulkan0) models, then the CPU models that may hold RAM beside the frontier.
      swap = {
        enable = true;
        routerEngine = "matrix";
        debug = true;
        coResidentTiers = [
          [
            "gemma-4-e2b"
            "gemma-4-e4b"
            "granite-4.2-3b"
            "granite-4.2-8b"
            "mimo-v2.6-qwen-9b"
            "ministral-3-3b-instruct"
            "ministral-3-3b-reasoning"
            "ministral-3-8b-instruct"
            "ministral-3-8b-reasoning"
            "olmo-3-7b-instruct"
            "qwen3.5-0.8b"
            "qwen3.5-2b"
            "qwen3.5-4b"
            "qwen3.5-9b"
            "tmax-2b"
            "tmax-9b"
          ]
          [ "qwen3.8-27b" ]
          [ "qwen3.5-35b-a3b" ]
        ];
        persistentModels = [ "qwen3.8-flash-next" ];
        vulkanDeviceSelect = "1002:73e3!";
      };

      # Boot profiles: WHICH ROUTERS ARE SERVED. A model is served when its
      # `hosts.brys.set` is one of these names.
      profiles = {
        desktop = {
          sets = [
            "main"
            "grunt"
            "surveyed"
          ];
        };
        appliance = {
          sets = [
            "main"
            "grunt"
            "surveyed"
          ];
        };
      };
    };
  };

  # ---------------------------------------------------------------- models
  #
  # One entry per served model. Identity on top; `hosts.brys` is the serving data.
  # `common` is what llama-server needs to load the model; `perf` is the preset INI.
  models = {
    "qwen3.8-flash-next" = {
      aliases = [
        "frontier"
        "qwen"
        "orchestrate-deep-slow"
      ];
      capabilities = {
        loadSeconds = 90;
        operation = "cpu";
      };
      pi = {
        contextWindow = 524288;
        maxTokens = 32768;
      };
      gpu = false;
      contextSize = 1048576;
      hosts.brys = {
        set = "main";
        servedContext = 1048576;
        common = {
          download = {
            enable = true;
            glob = "UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-*.gguf";
            minBytes = 10000000;
          };
          enable = true;
          hfFile = "UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf";
          hfRepo = "unsloth/Qwen3.8-Flash-Next-GGUF";
          mmproj = {
            enable = true;
            hfFile = "mmproj-F16.gguf";
            hfRepo = "unsloth/Qwen3.8-Flash-Next-GGUF";
          };
          perf = {
            batchSize = 4096;
            cacheRam = 8192;
            cacheTypeK = "q8_0";
            cacheTypeV = "q8_0";
            checkpointMinStep = 900;
            ctxCheckpoints = 32;
            kvUnified = true;
            mmap = null;
            parallel = 2;
            reasoning = "auto";
            reasoningEffort = "low";
            ropeFreqBase = 10000000;
            ropeScale = 4.0;
            ropeScaling = "yarn";
            sessionHeaders = "x-session-id";
            sessionMaxSessions = 64;
            ubatchSize = 4096;
            yarnOrigCtx = 262144;
          };
        };
      };
    };
    "qwen3.5-4b" = {
      aliases = [
        "grunt"
        "chat-dumb-fast"
        "code-quick-fast"
        "tiny-quick-fast"
      ];
      capabilities = {
        loadSeconds = 2;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "grunt";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3.5-4b.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
          };
        };
      };
    };
    "qwen3.5-9b" = {
      hosts.brys = {
        set = "grunt";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = false;
          hfFile = "qwen3.5-9b.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
          };
        };
      };
    };
    "gemma-4-12b" = {
      gpu = false;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "gemma-4-12b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "gemma-4-26b-a4b" = {
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "gemma-4-26b-a4b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "gemma-4-31b" = {
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "gemma-4-31b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "gemma-4-e2b" = {
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "gemma-4-e2b.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "gemma-4-e4b" = {
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "gemma-4-e4b.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "glm-4.7-flash" = {
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "glm-4.7-flash.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "granite-4.2-30b" = {
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "granite-4.2-30b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "granite-4.2-3b" = {
      aliases = [
        "tools-dumb-fast"
        "chat-dumb-fast-alt"
      ];
      capabilities = {
        loadSeconds = 1;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "granite-4.2-3b.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "granite-4.2-8b" = {
      aliases = [ "tools-std-fast-alt" ];
      capabilities = {
        loadSeconds = 3;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "granite-4.2-8b.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "lfm2.5-24b-a2b" = {
      aliases = [
        "chat-std-fast"
        "tools-std-fast"
      ];
      capabilities = {
        loadSeconds = 15;
        operation = "cpu";
      };
      gpu = false;
      contextSize = 32768;
      hosts.brys = {
        set = "surveyed";
        servedContext = 32768;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "lfm2.5-24b-a2b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "mellum-2.1-12b-a2.5b-thinking" = {
      aliases = [
        "reason-quick-fast"
        "code-std-fast-alt"
      ];
      capabilities = {
        loadSeconds = 12;
        operation = "cpu";
      };
      gpu = false;
      contextSize = 32768;
      hosts.brys = {
        set = "surveyed";
        servedContext = 32768;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "mellum-2.1-12b-a2.5b-thinking.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "mimo-v2.6-qwen-9b" = {
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "mimo-v2.6-qwen-9b.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "ministral-3-3b-instruct" = {
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "ministral-3-3b-instruct.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "ministral-3-3b-reasoning" = {
      aliases = [ "reason-quick-fast-alt" ];
      capabilities = {
        loadSeconds = 1;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "ministral-3-3b-reasoning.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "ministral-3-8b-instruct" = {
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "ministral-3-8b-instruct.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "ministral-3-8b-reasoning" = {
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "ministral-3-8b-reasoning.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "nemotron-3-nano-30b-a3b" = {
      aliases = [
        "reason-std-fast"
        "chat-std-mid-long"
      ];
      capabilities = {
        loadSeconds = 20;
        operation = "cpu";
      };
      gpu = false;
      contextSize = 32768;
      hosts.brys = {
        set = "surveyed";
        servedContext = 32768;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "nemotron-3-nano-30b-a3b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "nemotron-3.5-lightning-30b" = {
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "nemotron-3.5-lightning-30b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "north-mini-code-1.0" = {
      aliases = [
        "code-std-fast"
        "code-std-fast-moe"
      ];
      capabilities = {
        loadSeconds = 15;
        operation = "cpu";
      };
      gpu = false;
      contextSize = 32768;
      hosts.brys = {
        set = "surveyed";
        servedContext = 32768;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "north-mini-code-1.0.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "olmo-3-7b-instruct" = {
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "olmo-3-7b-instruct.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            extraFlags = [
              "--no-jinja"
              "--chat-template"
              "chatml"
            ];
            nGpuLayers = 99;
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "olmo-3.1-32b" = {
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "olmo-3.1-32b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "ornith-1.5-35b-a3b" = {
      aliases = [ "vision-std-fast-alt" ];
      capabilities = {
        loadSeconds = 25;
        operation = "cpu";
      };
      vision = true;
      gpu = false;
      contextSize = 32768;
      hosts.brys = {
        set = "surveyed";
        servedContext = 32768;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "ornith-1.5-35b-a3b.gguf";
          hfRepo = "surveyed";
          mmproj = {
            enable = true;
            hfFile = "mmproj-ornith-1.5-35b-a3b.gguf";
            hfRepo = "surveyed";
          };
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "qwen3-embedding-4b" = {
      aliases = [ "embed-std-fast" ];
      capabilities = {
        loadSeconds = 2;
        operation = "gpu";
      };
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3-embedding-4b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "qwen3-omni-30b-a3b" = {
      aliases = [ "audio-std-mid" ];
      capabilities = {
        loadSeconds = 20;
        operation = "cpu";
      };
      vision = true;
      gpu = false;
      contextSize = 32768;
      hosts.brys = {
        set = "surveyed";
        servedContext = 32768;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3-omni-30b-a3b.gguf";
          hfRepo = "surveyed";
          mmproj = {
            enable = true;
            hfFile = "qwen3-omni-30b-a3b-mmproj.gguf";
            hfRepo = "surveyed";
          };
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "qwen3-reranker-4b" = {
      aliases = [ "rank-std-fast" ];
      capabilities = {
        loadSeconds = 2;
        operation = "gpu";
      };
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3-reranker-4b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "qwen3-vl-30b-a3b" = {
      aliases = [
        "vision-std-fast"
        "vision-std-fast-moe"
      ];
      capabilities = {
        loadSeconds = 20;
        operation = "cpu";
      };
      vision = true;
      gpu = false;
      contextSize = 32768;
      hosts.brys = {
        set = "surveyed";
        servedContext = 32768;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3-vl-30b-a3b.gguf";
          hfRepo = "surveyed";
          mmproj = {
            enable = true;
            hfFile = "qwen3-vl-30b-a3b-mmproj.gguf";
            hfRepo = "surveyed";
          };
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "qwen3-vl-8b-instruct" = {
      aliases = [ "vision-quick-fast" ];
      capabilities = {
        loadSeconds = 3;
        operation = "gpu";
      };
      vision = true;
      gpu = false;
      contextSize = 32768;
      hosts.brys = {
        set = "surveyed";
        servedContext = 32768;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3-vl-8b-instruct.gguf";
          hfRepo = "surveyed";
          mmproj = {
            enable = true;
            hfFile = "qwen3-vl-8b-instruct-mmproj.gguf";
            hfRepo = "surveyed";
          };
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "qwen3.5-0.8b" = {
      aliases = [ "tiny-dumb-fast" ];
      capabilities = {
        loadSeconds = 1;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3.5-0.8b.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            kvUnified = true;
            nGpuLayers = 99;
            parallel = 4;
            threads = 8;
          };
        };
      };
    };
    "qwen3.5-0.8b-cpu" = {
      gpu = false;
      source = "qwen3.5-0.8b";
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3.5-0.8b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "qwen3.5-2b" = {
      aliases = [ "tiny-dumb-fast-alt" ];
      capabilities = {
        loadSeconds = 1;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3.5-2b.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            kvUnified = true;
            nGpuLayers = 99;
            parallel = 4;
            threads = 8;
          };
        };
      };
    };
    "qwen3.5-2b-cpu" = {
      gpu = false;
      source = "qwen3.5-2b";
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3.5-2b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "qwen3.5-35b-a3b" = {
      aliases = [ "chat-std-mid" ];
      capabilities = {
        loadSeconds = 25;
        operation = "cpu";
      };
      gpu = false;
      contextSize = 262144;
      hosts.brys = {
        set = "surveyed";
        servedContext = 262144;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3.5-35b-a3b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "qwen3.6-27b" = {
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3.6-27b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "qwen3.6-35b-a3b" = {
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3.6-35b-a3b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "qwen3.8-27b" = {
      aliases = [
        "chat-deep-slow"
        "code-deep-slow"
        "vision-deep-slow"
        "reason-deep-slow"
        "tools-deep-slow"
      ];
      capabilities = {
        loadSeconds = 40;
        operation = "cpu";
      };
      pi = {
        maxTokens = 8192;
      };
      vision = true;
      gpu = false;
      contextSize = 131072;
      hosts.brys = {
        set = "surveyed";
        servedContext = 131072;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3.8-27b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "seed-oss-36b" = {
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "seed-oss-36b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "tmax-2b" = {
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "tmax-2b.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            kvUnified = true;
            nGpuLayers = 99;
            parallel = 4;
            threads = 8;
          };
        };
      };
    };
    "tmax-2b-cpu" = {
      gpu = false;
      source = "tmax-2b";
      contextSize = 8192;
      hosts.brys = {
        set = "surveyed";
        servedContext = 8192;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "tmax-2b.gguf";
          hfRepo = "surveyed";
          perf = {
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
    "tmax-9b" = {
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "tmax-9b.gguf";
          hfRepo = "surveyed";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 8;
          };
        };
      };
    };
  };
}

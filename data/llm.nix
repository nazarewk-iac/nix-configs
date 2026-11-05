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
    # A remote router. Unlike `brys`, models here name `endpoint = "requesty"` and have no host
    # block, so they never appear in the local fleet catalog or the llama-swap serving set.
    requesty = {
      baseUrl = "https://router.requesty.ai/v1";
      api = "openai-completions";
      # The key is a sops secret at `/run/configs/llms/requesty/api-key` (llms.nonsensitive.sops
      # tree). The fallback reads opencode's own credential store, so a shell that has not switched
      # to the new sops tree yet still resolves the key instead of failing the whole provider.
      apiKey = "!cat /run/configs/llms/requesty/api-key 2>/dev/null || jq -r '.requesty.key // empty' \"$HOME/.local/share/opencode/auth.json\"";
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
            "gemma-4-e4b"
            "granite-4.2-3b"
            "granite-4.2-8b"
            "ministral-3-3b-reasoning"
            "qwen3.5-0.8b"
            "qwen3.5-2b"
            "qwen3.5-4b"
          ]
          [ "qwen3.5-35b-a3b" ]
        ];
        persistentModels = [ "qwen3.8-flash-next" ];
        vulkanDeviceSelect = "1002:73e3!";
      };

      # Boot profiles: WHICH ROUTERS ARE SERVED. A model is served when its
      # `hosts.brys.set` is one of these names.
      #
      # `retired` is deliberately NOT listed in any profile. A model there keeps its full
      # registration (file, download, perf, measurements) and is one word from being served
      # again, but llama-swap never spawns it and no alias points at it. Everything moved
      # there was measured during the 2026 survey and then superseded, usually because it was
      # slower than the frontier or duplicated a tier. Keeping the block (rather than deleting
      # it) is what makes the docs/local-llms.md measurements reproducible.
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
    # A cloud model: served by Requesty, not by any local host. `endpoint` keeps it out of the
    # local fleet and its serving arithmetic; `contextSize` is only the client budget.
    "deepseek-v4.1-flash-1017" = {
      endpoint = "requesty";
      aliases = [
        "ds4"
        "remote"
      ];
      capabilities = {
        operation = "remote";
      };
      pi = {
        contextWindow = 128 * K;
        maxTokens = 16 * K;
      };
      contextSize = 128 * K;
    };
    "qwen3.8-flash-next" = {
      # The deep aliases landed here when qwen3.8-27b was dropped. Measured on 2026-11-04 on
      # the same prompt: 27b on 8 CPU threads produced 0.80 tok/s, flash-next on 16 threads
      # 2.36 tok/s. The dense 27b was three times slower AND had a smaller window (131k vs
      # 1M), so it bought nothing for a deep tier and cost a model slot.
      aliases = [
        "frontier"
        "qwen"
        "orchestrate-deep-slow"
        "chat-deep-slow"
        "code-deep-slow"
        "reason-deep-slow"
        "tools-deep-slow"
      ];
      capabilities = {
        loadSeconds = 90;
        operation = "cpu";
      };
      pi = {
        contextWindow = 524288;
        maxTokens = 32768;
      };
      # A reasoning model served with `perf.reasoning = "auto"`. `thinkingLevelMap` tells the Pi
      # client which request value each level sends; Qwen's template accepts `low|medium|xhigh`
      # (there is no `none`). `minimal` shares the template's `low`, and `high` maps to `xhigh`.
      # llama-swap does not advertise this, so the data must: without it Pi lists the model as
      # non-thinking and forces `--thinking off` (measured: the orchestrator ran at 0 thinking).
      reasoning = {
        format = "qwen";
        levels = {
          low = "low";
          medium = "medium";
          high = "xhigh";
        };
      };
      gpu = false;
      # Vision is deliberately OFF. The projector loads ~0.8 GB and every image prompt pays a
      # CPU prefill: measured 2026-11-04, a 256px icon took 259 s and a 2560px terminal
      # screenshot did not finish in 900 s. Use the VL models for images.
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
        "code-std-fast"
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
        set = "retired";
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
        set = "retired";
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
    "gemma-4-e2b" = {
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "retired";
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
      # Effective 4.5B (8B with embeddings), native text + image + audio. Measured 2026-11-05
      # on the W6600 (docs/local-llms.md, "Gemma 4 E4B"): tool calling 6/6 including parallel
      # calls and JSON-in-argument escaping, UI screenshots and tables correct, dense OCR 17/18
      # at --image-max-tokens 1120, native audio ASR correct. Decode is ~15 tok/s and prefill
      # ~80 tok/s, so it is a serial workhorse, not a fast tier. GPU is only ~6% ahead of CPU
      # on this card; it stays on the GPU because that costs nothing when co-resident.
      capabilities = {
        loadSeconds = 25;
        operation = "gpu";
      };
      vision = true;
      gpu = true;
      # The card's native window is 128K, but prefill at ~80 tok/s makes anything past ~30k
      # unusable in practice (30k took 1549 s). Serve what is actually usable.
      contextSize = 32768;
      hosts.brys = {
        set = "surveyed";
        servedContext = 32768;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "gemma-4-e4b.gguf";
          hfRepo = "surveyed";
          # No mmproj was configured before, so the model had no vision and no audio at all.
          mmproj = {
            enable = true;
            hfFile = "mmproj-gemma-4-E4B-it-Q8_0.gguf";
            hfRepo = "surveyed";
          };
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 16;
            # 1120 is the OCR lever: it took dense-text transcription from 14/18 to 17/18
            # exact. The model's own budget ladder is 70/140/280/560/1120.
            imageMaxTokens = 1120;
          };
        };
      };
    };
    "glm-4.7-flash" = {
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "retired";
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
        set = "retired";
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
        set = "retired";
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
        set = "retired";
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
        set = "retired";
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
        set = "retired";
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
    "olmo-3-7b-instruct" = {
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "retired";
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
    "ornith-1.5-35b-a3b" = {
      # The best reader of dense terminal text in the 2026-11-04 probe: it alone got the failed
      # unit count right, the /nix/var/nix symlink target right, and the emergency-mode cause right.
      aliases = [
        "vision-deep-slow"
        "vision-std-fast-alt"
      ];
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
      # vision-quick-fast is retired: it resolved to this same model, so the "quick" tier was
      # the standard tier with a different sample. Measured on a 256px icon it said "pig"
      # where the same model said "elephant" — a label that promised nothing.
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
      contextSize = 16384;
      hosts.brys = {
        set = "retired";
        servedContext = 16384;
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
      contextSize = 16384;
      hosts.brys = {
        set = "retired";
        servedContext = 16384;
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
    "qwen3.6-35b-a3b" = {
      gpu = false;
      contextSize = 8192;
      hosts.brys = {
        set = "retired";
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
    "tmax-2b" = {
      gpu = true;
      contextSize = 16384;
      hosts.brys = {
        set = "retired";
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
      contextSize = 16384;
      hosts.brys = {
        set = "retired";
        servedContext = 16384;
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
        set = "retired";
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

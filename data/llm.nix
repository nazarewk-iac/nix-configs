# The single source of truth for the LLM fleet.
#
# ## What lives here
#
# One entry per SERVED MODEL, plus the endpoint it is reached through and the
# cross-model serving data for each host. Every consumer derives from this file
# and none of them repeats a model id, an alias or a context size:
#
#   * the server   `hosts-den/brys/llm.nix` projects `mkServerModels data "brys" <profile>`
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
    # Direct loopback path to brys' llama-swap, valid ONLY when a client runs on
    # brys itself (offline capability). Other clients use the `litellm` gateway.
    brys = {
      baseUrl = "http://127.0.0.1:9530/v1";
      api = "openai-completions";
      apiKey = "!cat /run/configs/llms/llama-server/api-keys/default";
      localHost = "brys";
    };
    # The second local llama-swap host (a laptop, RX 6800M). Same OpenAI-compatible
    # shape as `brys`; the shared API key file is mounted on the host too. Clients
    # normally reach this through the LiteLLM gateway, but the direct URL stays valid.
    # Direct loopback path to oams' llama-swap, valid ONLY on oams (offline). The
    # compat proxy on 9530 gives the same DSML translation an off-host client gets.
    oams = {
      baseUrl = "http://127.0.0.1:9530/v1";
      api = "openai-completions";
      apiKey = "!cat /run/configs/llms/llama-server/api-keys/default";
      localHost = "oams";
    };
    # The LiteLLM gateway on etra: one OpenAI-compatible entrypoint in front of the
    # whole fleet, with load-balancing and failover across brys and oams. It exposes
    # every served ALIAS (see lib/llm.nix `mkPiModelsJson`), so a client picks an
    # alias and the gateway chooses the host. The key is the gateway master key; it is
    # read from the client's runtime secrets the same way the direct endpoints are.
    litellm = {
      # The gateway is exposed on its own subdomain by etra's Caddy over HTTPS with
      # an internal-CA leaf (resolved via NetBird DNS zones).
      baseUrl = "https://litellm.etra.priv.nb.net.int.kdn.im/v1";
      api = "openai-completions";
      # A non-admin client key (all-models allow-list), NOT the master key: the
      # gateway custom_auth validates it and scopes it — the master key stays admin
      # only. Shared via the llms sops tree so every client host reads the same token.
      apiKey = "!cat /run/configs/llms/litellm/client-key";
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
        # One tier of mutually-exclusive small models. They co-reside with the frontier in `main`:
        # flash-next holds ~21 GiB of VRAM at `nCpuMoe = 24` and the biggest member here is
        # 2.6 GB, so the pair fits the 32 GB card (measured 24.2 GiB total).
        #
        # `qwen3.5-35b-a3b` is deliberately NOT a tier any more. It needs 20.5 GB of VRAM on its
        # own, which no longer fits beside a 21 GiB frontier on the 32 GB card. It stays served on
        # its router and evicts the frontier when it loads.
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
        ];
        vulkanDeviceSelect = "1002:7551!";
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

    # The laptop host. It serves only SMALL models that fit the 12 GB RX 6800M
    # (docs/tasks/2026-11/oams-llm-host/). No grunt/surveyed split: one `main`
    # router plus a `swap` that lets llama-swap evict between the few models. The
    # GPU device pin is 1002:73df (the 6800M), not brys' 1002:7551.
    oams = {
      package = "llama-cpp-sessions-vulkan-noblas";
      defaultThreads = 12;
      modelsDir = "/var/lib/kdn/llms/models";
      download = {
        tokenFile = "/run/configs/llms/huggingface/token";
        mode = "fast-polite";
        xetConcurrency = 4;
      };
      apiKeyDir = "/run/configs/llms/llama-server/api-keys";
      # The small models are stateless; no disk session cache on this host.
      sessionStore = {
        path = "/var/lib/kdn/llms/sessions";
        group = "llama-cpp-sessions";
        maxBytes = 4 * 1024 * 1024 * 1024;
      };
      routers = { };
      swap = {
        enable = true;
        routerEngine = "matrix";
        debug = true;
        # Only the models that fit in 12 GB are co-residency-tiered; the MoE
        # candidates go on a RAM tier once measured.
        # One Vulkan0 tier: the small fast models and the MoE winner are mutually
        # exclusive on the card (llama-swap evicts between them).
        coResidentTiers = [
          [
            "gemma-4-e4b"
            "qwen3.5-2b"
            "qwen3.5-0.8b"
            "granite-4.2-3b"
          ]
        ];
        vulkanDeviceSelect = "1002:73df!";
      };
      profiles = {
        desktop = {
          sets = [ "main" ];
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
      # No aliases: the pi static `requesty` provider uses the entry id as the wire
      # name, and Requesty only accepts canonical ids — the old aliases `ds4`/`remote`
      # were 400 on a direct call (dropped 2026-11-13).
      capabilities = {
        operation = "remote";
      };
      # Native vision and a native 1M window (Requesty reports `context_window`
      # 1048576 for both the deepinfra and runware deployments). The id is also
      # Requesty's AGGREGATE alias: a request for `deepseek-v4.1-flash-1017` routes
      # across those providers, and Requesty answers with the provider-scoped id.
      vision = true;
      pi = {
        contextWindow = 1024 * K;
        maxTokens = 16 * K;
      };
      contextSize = 1024 * K;
    };
    # A cloud model: served by Requesty, not by any local host. `endpoint` keeps it out of the
    # local fleet and its serving arithmetic; the id is Requesty's canonical aggregate name
    # (`alibaba/qwen3.8-flash`), which the direct `requesty` endpoint routes and the gateway
    # serves as `requesty/alibaba/qwen3.8-flash`. Enabled on the account 2026-11-13 as the
    # cheaper sibling of `tensorx/qwen3.8-flash-next`; it is the pi `planner` sub-agent's model
    # (auxiliary; the pi harness default is `deepseek-v4.1-flash-1017` — see
    # modules/den/aspects/pi-client.nix). No `reasoning` block: the deployment takes the
    # upstream `reasoning_effort` pass-through (verified 2026-11-13), so no client-side map.
    "qwen3.8-flash" = {
      endpoint = "requesty";
      capabilities = {
        operation = "remote";
      };
      # Native 1M window and 128K max output (Requesty `alibaba/qwen3.8-flash`), vision.
      vision = true;
      pi = {
        contextWindow = 1024 * K;
        maxTokens = 16 * K;
      };
      contextSize = 1048576;
    };
    # ------------------------------------------------------------------ Strata profiles
    # Strata is not llama-server: each entry names a complete command instead of a generated
    # llama-server invocation. `strata-serve` (hosts-den/brys/strata-serve.nix + .sh) materialises
    # one profile config and runs `strata serve` in the foreground on the port llama-swap passes.
    # The profiles are mutually exclusive (they share the `main` group) and a switch costs one
    # engine reload, 50-70 s. Measured: docs/tasks/2026-11/brys-r9700-model-fit/measurements.md
    #
    # Three names describe the frontier and that is the whole surface:
    #
    #   `qfn`        profile-neutral. It asks the manager for `auto`, which keeps whatever profile is
    #                current, so a harness never reloads the engine by asking for it. A request that
    #                is already in flight when somebody switches the profile is completed, not cut:
    #                the manager drains the engine on a lease count (see strata-manager.py).
    #   `qfn-max`    forces the `max` profile (UD-IQ4_XS on the whole card). Picking it reloads.
    #   `qfn-colo`   forces the `omni-fast` profile (IQ2_XS + 21.5 GB reserve, the companion fits).
    #                Picking it reloads. `omni-max` stays reachable through the manager API only.
    "qfn" = {
      capabilities = {
        rates = {
          decode = 73.1;
          prefill = 1900.0;
          mode = "GPU";
        };
        loadSeconds = 60;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 1048576;

      # `auto`: keep the manager's current profile, so the model name cannot trigger a reload.
      command = [
        "/run/current-system/sw/bin/strata-select"
        "auto"
        "--port"
        "\${PORT}"
      ];
      hosts.brys = {
        set = "main";
        servedContext = 1048576;
        common = {
          enable = true;
          hfFile = "UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf";
          hfRepo = "unsloth/Qwen3.8-Flash-Next-GGUF";
          download.enable = false;
          perf.contextSize = 1048576;
        };
      };
    };
    "qfn-max" = {
      aliases = [ ];
      capabilities = {
        rates = {
          decode = 42.3;
          prefill = 1000.0;
          mode = "GPU";
        };
        loadSeconds = 60;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 1048576;

      # Forces the whole-card profile; a caller that asks for this name pays the reload.
      command = [
        "/run/current-system/sw/bin/strata-select"
        "max"
        "--port"
        "\${PORT}"
      ];
      hosts.brys = {
        set = "main";
        servedContext = 1048576;
        common = {
          enable = true;
          hfFile = "UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf";
          hfRepo = "unsloth/Qwen3.8-Flash-Next-GGUF";
          download.enable = false;
          perf.contextSize = 1048576;
        };
      };
    };
    "qfn-max-colo" = {
      aliases = [ ];
      capabilities = {
        rates = {
          decode = 42.3;
          prefill = 1000.0;
          mode = "GPU";
        };
        loadSeconds = 60;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 1048576;

      # The best pack WITH the reserve: qfn at 42 t/s at 1M, the companion at full speed beside it.
      command = [
        "/run/current-system/sw/bin/strata-select"
        "omni-max"
        "--port"
        "\${PORT}"
      ];
      hosts.brys = {
        set = "main";
        servedContext = 1048576;
        common = {
          enable = true;
          hfFile = "UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf";
          hfRepo = "unsloth/Qwen3.8-Flash-Next-GGUF";
          download.enable = false;
          perf.contextSize = 1048576;
        };
      };
    };
    "qfn-fast-colo" = {
      aliases = [ ];
      capabilities = {
        rates = {
          decode = 71.6;
          prefill = 1300.0;
          mode = "GPU";
        };
        loadSeconds = 60;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 1048576;

      # The fast pack WITH the reserve: qfn at 72 t/s at 1M, the companion at full speed beside it.
      command = [
        "/run/current-system/sw/bin/strata-select"
        "omni-fast"
        "--port"
        "\${PORT}"
      ];
      hosts.brys = {
        set = "main";
        servedContext = 1048576;
        common = {
          enable = true;
          hfFile = "IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf";
          hfRepo = "surveyed";
          download.enable = false;
          perf.contextSize = 1048576;
        };
      };
    };

    # ---------------------------------------------------------------- image and video editing
    # Both editors join the `main` set, the same one the frontier profiles use, so llama-swap evicts
    # QFN for them and they for QFN. That is the hardware's verdict: Qwen-Image-Edit at Q8_0 is
    # 21.8 GB plus a 9.4 GB encoder, and VACE 14B at fp8 wants most of the card too.
    #
    # They are DISABLED until the serving stack is proven (docs/tasks/2026-11/image-video-editing-models):
    # llama.cpp cannot run a diffusion model, so the entry is a `stable-diffusion-cpp` server on the
    # port llama-swap hands over, not a llama-server. The `command` below is the intended shape and
    # is deliberately left out until the smoke test passes, so nothing advertises a model that no
    # process serves.
    "qwen-image-edit" = {
      aliases = [ ];
      capabilities = {
        loadSeconds = 90;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 4096;
      hosts.brys = {
        set = "main";
        servedContext = 4096;
        common = {
          enable = false;
          hfFile = "Qwen-Image-Edit-2511-Q8_0.gguf";
          hfRepo = "unsloth/Qwen-Image-Edit-2511-GGUF";
          download.enable = false;
          perf.contextSize = 4096;
        };
      };
    };
    "longcat-image-edit" = {
      aliases = [ ];
      capabilities = {
        loadSeconds = 40;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 4096;
      hosts.brys = {
        set = "main";
        servedContext = 4096;
        common = {
          enable = false;
          hfFile = "LongCat-Image-Edit-Turbo/LongCat-Image-Edit-Turbo.safetensors";
          hfRepo = "meituan-longcat/LongCat-Image-Edit-Turbo";
          download.enable = false;
          perf.contextSize = 4096;
        };
      };
    };
    "wan-vace-14b" = {
      aliases = [ ];
      capabilities = {
        loadSeconds = 120;
        operation = "gpu";
      };
      gpu = true;
      contextSize = 4096;
      hosts.brys = {
        set = "main";
        servedContext = 4096;
        common = {
          enable = false;
          hfFile = "wan2.1_vace_14B_fp8.safetensors";
          hfRepo = "Wan-AI/Wan2.1-VACE-14B";
          download.enable = false;
          perf.contextSize = 4096;
        };
      };
    };

    "qwen3.8-flash-next" = {
      # RE-ENABLED 2026-11-18 on the R9700, measured. The 2026-11-13 retirement was correct for
      # the 8 GB W6600 (2.36 t/s decode, CPU-only). The 32 GB R9700 runs the same model at
      # **20.4 t/s decode / 52.5 t/s prefill at 32k context**, with 21 GiB of VRAM and a small
      # model still able to co-reside. The harness change is `nCpuMoe`: the MoE experts of the
      # first 24 of 48 layers stay in RAM, the rest live in VRAM. Measurements:
      # docs/tasks/2026-11/brys-r9700-model-fit/measurements.md.
      #
      # The quant moved to `UD-IQ1_S` (62 GB, 3 shards). `UD-IQ4_XS` (the old 88 GB 3-shard set)
      # leaves too little RAM for the KV cache plus a co-resident model, and it is a stale
      # upstream revision. The measured 32k tune does not transfer to another quant.
      # No aliases: this llama.cpp path is the fallback behind the Strata `qfn` entries, which own
      # the frontier names now. Once those four names were collapsed to `qfn` / `qfn-max` /
      # `qfn-colo` / `qwen3-omni`, keeping a second model on the same alias would make the gateway
      # expose a name that resolves to whichever model folded last.
      aliases = [ ];
      capabilities = {
        # Measured 2026-11-18 on the R9700 (gpu-r9700), llama.cpp Vulkan, `--n-cpu-moe 26`,
        # 64k context, mmap load. Not an estimate.
        rates = {
          decode = 21.9;
          # Sustained prefill, measured 2026-11-18 in four lengths (2.5k/8.5k/11k/21.5k tokens):
          # 257/289/272/255 t/s. A short prompt reports far less because the fixed overheads
          # dominate; the fleet derives its stream timeout from this number, so it must be the
          # sustained rate, not a 16-token reading.
          prefill = 255.0;
          mode = "GPU";
        };
        # 62 GB of weights from ZFS, then the load. Measured ~30 s warm, more when cold.
        loadSeconds = 45;
        operation = "gpu";
      };
      pi = {
        contextWindow = 65536;
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
      gpu = true;
      # Vision is deliberately OFF. The projector loads ~0.8 GB and every image prompt pays a
      # CPU prefill. Use the VL models for images.
      contextSize = 262144;
      hosts.brys = {
        # Retired in favour of the `qfn-*` Strata profiles above; the llama.cpp path stays
        # registered as the fallback and is one word from serving again.
        set = "retired";
        # 64k, not 32k: at `nCpuMoe 26` the 64k KV cache costs the same VRAM as the 32k tune at
        # `nCpuMoe 24` (19.8 GiB) and decodes slightly faster (20.9 vs 20.4 t/s). Measured
        # 2026-11-18, docs/tasks/2026-11/brys-r9700-model-fit/measurements.md.
        servedContext = 65536;
        common = {
          download = {
            enable = true;
            glob = "UD-IQ1_S/Qwen3.8-Flash-Next-UD-IQ1_S-*.gguf";
            minBytes = 10000000;
          };
          enable = true;
          hfFile = "UD-IQ1_S/Qwen3.8-Flash-Next-UD-IQ1_S-00001-of-00003.gguf";
          hfRepo = "unsloth/Qwen3.8-Flash-Next-GGUF";
          perf = {
            batchSize = 2048;
            cacheRam = 8192;
            cacheTypeK = "q8_0";
            cacheTypeV = "q8_0";
            checkpointMinStep = 900;
            ctxCheckpoints = 8;
            kvUnified = true;
            # mmap, NOT `none`: with `none` the 62 GB read plus the Vulkan upload is what wedged
            # RADV on the 102 GB GLM model; mmap is the safe path on this host.
            loadMode = "mmap";
            # The expert split that measured 20.9 t/s at 64k in 19.8 GiB. Raising it costs
            # decode; lowering it overcommits VRAM and the KV cache evicts experts (14.6 t/s at
            # `nCpuMoe 6` with a 32k window).
            nCpuMoe = 26;
            nGpuLayers = 99;
            parallel = 1;
            reasoning = "auto";
            reasoningEffort = "low";
            sessionHeaders = "x-session-id";
            sessionMaxSessions = 16;
            ubatchSize = 512;
            # llama-server's auto-fit aborts when a model does not fit and `--n-gpu-layers` is
            # set, then silently serves from the CPU. The explicit placement above is the whole
            # point, so the fit pass is turned off.
            extraFlags = [
              "--fit"
              "off"
            ];
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
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 60.8;
          prefill = 158.0;
          mode = "GPU";
        };
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
      capabilities = {
        operation = "cpu";
        # Measured throughput on CPU (docs/local-llms.md unified table).
        rates = {
          decode = 5.6;
          prefill = 40.8;
          mode = "CPU";
        };
      };
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
      capabilities = {
        operation = "cpu";
        # Measured throughput on CPU (docs/local-llms.md unified table).
        rates = {
          decode = 5.76;
          prefill = 10.4;
          mode = "CPU";
        };
      };
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
      capabilities = {
        operation = "cpu";
        # Measured throughput on CPU (docs/local-llms.md unified table).
        rates = {
          decode = 14.5;
          prefill = 67.7;
          mode = "CPU";
        };
      };
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
      capabilities = {
        operation = "gpu";
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 25.4;
          prefill = 149.4;
          mode = "GPU";
        };
      };
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
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 15.7;
          prefill = 84.5;
          mode = "GPU";
        };
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
      # oams: the 12 GB RX 6800M runs this model 6-9x faster than the W6600. Same file and
      # mmproj; more threads because the laptop CPU is weaker per core.
      hosts.oams = {
        set = "main";
        servedContext = 32768;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "gemma-4-e4b.gguf";
          hfRepo = ".";
          mmproj = {
            enable = true;
            hfFile = "mmproj-gemma-4-E4B-it-Q8_0.gguf";
            hfRepo = ".";
          };
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 12;
            imageMaxTokens = 1120;
          };
        };
      };
    };
    "glm-4.7-flash" = {
      capabilities = {
        operation = "cpu";
        # Measured throughput on CPU (docs/local-llms.md unified table).
        rates = {
          decode = 11.5;
          prefill = 46.5;
          mode = "CPU";
        };
      };
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
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 83.9;
          prefill = 223.6;
          mode = "GPU";
        };
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
      hosts.oams = {
        set = "main";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "granite-4.2-3b.gguf";
          hfRepo = ".";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 12;
          };
        };
      };
    };
    "granite-4.2-8b" = {
      aliases = [ "tools-std-fast-alt" ];
      capabilities = {
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 38.6;
          prefill = 146.0;
          mode = "GPU";
        };
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
      capabilities = {
        operation = "cpu";
        # Measured throughput on CPU (docs/local-llms.md unified table).
        rates = {
          decode = 5.7;
          prefill = 28.1;
          mode = "CPU";
        };
      };
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
      capabilities = {
        operation = "gpu";
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 79.3;
          prefill = 1369.0;
          mode = "GPU";
        };
      };
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
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 80.9;
          prefill = 933.0;
          mode = "GPU";
        };
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
      capabilities = {
        operation = "gpu";
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 38.4;
          prefill = 576.0;
          mode = "GPU";
        };
      };
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
      capabilities = {
        operation = "gpu";
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 38.9;
          prefill = 458.0;
          mode = "GPU";
        };
      };
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
      capabilities = {
        operation = "cpu";
        # Measured throughput on CPU (docs/local-llms.md unified table).
        rates = {
          decode = 12.9;
          prefill = 44.0;
          mode = "CPU";
        };
      };
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
      capabilities = {
        operation = "gpu";
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 40.4;
          prefill = 136.0;
          mode = "GPU";
        };
      };
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
    "qwen3-omni" = {
      aliases = [ ];
      # The gate in front of the model. It refuses the request with a readable 409 unless the engine
      # has a VRAM reserve for it, and a body field (`kdn_switch_to`) lets the caller ask for the
      # switch in the same request. Only a process on the entry port can read the body, so the gate
      # starts the server itself: llama-swap starts the gate, the gate starts llama-server.
      wrapper = [
        "/run/current-system/sw/bin/kdn-inference-helpers"
        "gate"
        "--name"
        "qwen3-omni"
        "--"
      ];
      # Nobody remembers to unload a companion. An hour of idleness evicts it, and the manager's
      # companion watcher then returns the engine to the whole-card profile by itself.
      ttl = 3600;
      capabilities = {
        loadSeconds = 20;
        operation = "gpu";
      };
      vision = true;
      gpu = true;
      contextSize = 32768;
      hosts.brys = {
        set = "surveyed";
        servedContext = 16384;
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
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 64.7;
          prefill = 500.9;
          mode = "GPU";
        };
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
      hosts.oams = {
        set = "main";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3.5-0.8b.gguf";
          hfRepo = ".";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 12;
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
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 116.8;
          prefill = 273.5;
          mode = "GPU";
        };
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
      hosts.oams = {
        set = "main";
        servedContext = 16384;
        common = {
          download = {
            enable = false;
          };
          enable = true;
          hfFile = "qwen3.5-2b.gguf";
          hfRepo = ".";
          perf = {
            device = "Vulkan0";
            nGpuLayers = 99;
            parallel = 1;
            threads = 12;
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
        # Measured throughput on CPU (docs/local-llms.md unified table).
        rates = {
          decode = 9.2;
          prefill = 45.9;
          mode = "CPU";
        };
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
      capabilities = {
        operation = "gpu";
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 110.7;
          prefill = 311.0;
          mode = "GPU";
        };
      };
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
      capabilities = {
        operation = "gpu";
        # Measured throughput on GPU (docs/local-llms.md unified table).
        rates = {
          decode = 36.9;
          prefill = 121.0;
          mode = "GPU";
        };
      };
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

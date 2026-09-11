# The `llm` slot, as a den aspect. It ports `modules/slots/llm/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It serves several local GGUF models from one `llama-server` process in **router mode**. The router
# owns one HTTP API and it loads or unloads a single model on demand. `--models-max 1` keeps exactly
# one model resident, so the other models stay on disk.
#
# The router binds the loopback address only. A LAN endpoint reaches it through one Caddy vhost with
# a consumer-supplied certificate, in front of one OpenCode DSML compat proxy. Caddy is the one
# process that opens a firewall port, and it opens 80 and 443 only.
#
# It also adds one oneshot systemd service that downloads every enabled model, one at a time.
#
# ## The class
#
# `nixos` only. The slot emits one target, `nixos`, so this aspect declares one class. Every option
# lives inside that target, next to the code that reads it — the same shape as ./ca.nix.
#
# ## The family
#
# Three aspects hold what three slot files held:
#
# | Aspect | Class | What it adds |
# |---|---|---|
# | `llm` (this file) | `nixos` | the router, the LAN gate, the download service |
# | `llm-client` | `devenv` | one opencode provider per LAN endpoint |
# | `llm-proxy` | `nixos` + `devenv` | standalone compat-proxy instances |
#
# No aspect includes another. The slots are independent too: this file runs its own inline
# compat-proxy unit and it never reads the proxy slot's options.
#
# DECISION TO REVISE: this aspect duplicates the proxy unit that ./llm-proxy.nix already knows how to
# write. A later commit can make this aspect `includes = [ kdn.llm-proxy ]` and write one instance
# into `kdn.llm.proxy.instances`, exactly as ./jj.nix writes an `mcp` backend. That is a behaviour
# change (the unit name and the environment set both move), so it needs its own commit and its own
# verification.
#
# ## The de-personalized port
#
# Five values named the creator's own network. Every one is neutral here, and in the slot too:
#
#  * `domain` gave one homelab fully-qualified name as its example. The example now names a
#    placeholder domain.
#  * `certs.sans` gave two more of the same. Same treatment.
#  * `certs.listenAddresses` gave two real addresses, one LAN and one overlay. The example now names
#    two documentation-range addresses.
#  * `modelsDir` had no default at all, so the aspect could not evaluate without consumer data. It
#    now defaults to a neutral system path.
#  * the preset generator held a fixed thread count for one 16-core machine. It is an option now,
#    and the default omits the flag. The slot holds the same option now.
#
# ## The LAN gate is optional now
#
# The slot required `domain`, `certs.certFile` and `certs.keyFile`, with no default. An aspect body
# is unconditional, so a required option with no default makes inclusion alone an evaluation error.
# All three are nullable here, and the Caddy vhost plus the firewall ports appear only when all three
# hold a value. So inclusion gives a loopback router, and the LAN gate is opt-in.
#
# DECISION TO REVISE: this splits one slot behaviour into two states. A later commit can move the LAN
# gate into its own aspect that includes this one, in the shape of the `mcp` family.
#
# ## One defect the port fixes
#
# The slot declares `models.<name>.download.enable` and never reads it, so a model that asks for no
# download gets one anyway. This aspect reads the option.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. The slot's `kdn.llm.local.enable` is gone. The
#    per-instance `enable` flags stay: each one selects a member of an attribute set, and an empty
#    set is already a no-op. See ./ca.nix.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.llm.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.llm.local;

      hf = lib.getExe pkgs.python3Packages.huggingface-hub;

      # The compat proxy comes from a plain `callPackage`, with no overlay. The slot reads
      # `pkgs.kdn.opencode-compat-proxy`, so a consumer must add this repository's `packages` overlay
      # first. A relative path needs no overlay. ./mcp-snoop.nix carries the same pattern.
      compatProxyPkg = pkgs.callPackage ../../../packages/opencode-compat-proxy { };

      enabledModels = lib.filterAttrs (_: m: m.enable) cfg.models;

      # The download set. The slot filters on `m.enable` alone, so `download.enable` never took
      # effect. This reads both.
      downloadModels = lib.filterAttrs (_: m: m.download.enable) enabledModels;

      # Absolute path of a downloaded model file inside `modelsDir`: <modelsDir>/<hfRepo>/<hfFile>.
      modelFile =
        name:
        let
          m = cfg.models.${name};
        in
        "${cfg.modelsDir}/${m.hfRepo}/${m.hfFile}";

      # Absolute path of a draft model file. Same layout as a model file.
      draftFile =
        name:
        let
          d = cfg.models.${name}.draft;
        in
        "${cfg.modelsDir}/${d.hfRepo}/${d.hfFile}";

      # Render one per-model preset section. Each key maps to one `llama-server` flag, minus the
      # leading dashes, and the router expands it onto that model's child process. A router-owned key
      # (host, port, api-key, alias routing) never appears here. Every global default folds into
      # every section, because some builds honour no `[*]` catch-all section.
      presetSection =
        name:
        let
          m = cfg.models.${name};
          perf = m.perf;
          threads = if perf.threads != null then perf.threads else cfg.defaultThreads;
        in
        lib.concatLines (
          [
            "[${name}]"
            "model = ${modelFile name}"
          ]
          ++ lib.optionals (threads != null) [
            "threads = ${toString threads}"
          ]
          ++ [
            "flash-attn = ${perf.flashAttention}"
          ]
          ++ lib.optionals (perf.cpuRange != null) [
            "cpu-range = ${perf.cpuRange}"
            "cpu-strict = ${if perf.cpuStrict then "1" else "0"}"
          ]
          ++ lib.optionals (perf.loadMode != null) [
            "load-mode = ${perf.loadMode}"
          ]
          ++ lib.optionals (perf.contextSize != null) [
            "ctx-size = ${toString perf.contextSize}"
          ]
          ++ lib.optionals (m.aliases != [ ]) [
            "alias = ${lib.concatStringsSep "," m.aliases}"
          ]
          ++ [
            "mmap = ${if perf.mmap then "on" else "off"}"
            "parallel = ${toString perf.parallel}"
            "reasoning = ${perf.reasoning}"
          ]
          ++ lib.optionals m.draft.enable [
            "spec-type = ${perf.specType}"
            "model-draft = ${draftFile name}"
          ]
          ++ lib.optionals (m.draft.enable && perf.specDraftNMax != null) [
            "spec-draft-n-max = ${toString perf.specDraftNMax}"
          ]
          ++ lib.optionals (m.draft.enable && perf.specDraftPMin != null) [
            "spec-draft-p-min = ${toString perf.specDraftPMin}"
          ]
          ++ lib.optionals (m.draft.enable && perf.specDraftPrio != null) [
            "spec-draft-prio = ${toString perf.specDraftPrio}"
          ]
        );

      # The model set of one router. `"main"` names the primary `services.llama-cpp` router; any
      # other name selects the models whose `mainRouter` matches it.
      routerModels =
        routerName: lib.filterAttrs (_: m: m.enable && m.mainRouter == routerName) cfg.models;

      # The filtered preset INI of one router. The primary keeps its own store name.
      presetIni =
        routerName:
        let
          iniName = if routerName == "main" then "models-preset.ini" else "models-router-${routerName}.ini";
        in
        pkgs.writeText iniName (
          lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: _: presetSection name) (routerModels routerName)
          )
        );

      # Every enabled extra router. `"main"` stays on `services.llama-cpp`.
      enabledRouters = lib.filterAttrs (name: _: name != "main") (
        lib.filterAttrs (_: r: r.enable) cfg.routers
      );

      # One `ROUTER_<NAME>_URL` and one `ROUTER_<NAME>_MODELS` pair per extra router. The compat
      # proxy reads the URL from the uppercase key, and it answers to every model id in the MODELS
      # value on that upstream. Anything else falls back to `UPSTREAM_URL`.
      #
      # A router name must be lowercase alphanumeric, so the uppercase key round-trips through the
      # proxy's own hyphenated slug. The assertion below states that rule.
      routerProxyEnv =
        lib.mapAttrs' (
          name: r: lib.nameValuePair "ROUTER_${lib.toUpper name}_URL" "http://127.0.0.1:${toString r.port}"
        ) enabledRouters
        // lib.mapAttrs' (
          name: _:
          lib.nameValuePair "ROUTER_${lib.toUpper name}_MODELS" (
            lib.concatStringsSep "," (
              lib.concatMap (modelName: [ modelName ] ++ (cfg.models.${modelName}.aliases or [ ])) (
                builtins.attrNames (routerModels name)
              )
            )
          )
        ) enabledRouters;

      # One raw systemd unit per extra router. It copies the primary unit's ExecStart shape and its
      # hardening.
      routerUnits = lib.mapAttrs' (
        name: r:
        lib.nameValuePair "llama-cpp-router-${name}" {
          description = "llama-server router for the ${name} model set";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          wants = [ "network.target" ];

          serviceConfig = {
            ExecStart = lib.concatStringsSep " " (
              [
                "${cfg.package}/bin/llama-server"
                "--host ${cfg.server.host}"
                "--port ${toString r.port}"
                "--models-preset ${presetIni name}"
                "--models-max ${toString r.modelsMax}"
                "--sleep-idle-seconds -1"
                "--threads ${toString r.threads}"
              ]
              ++ lib.optionals (r.apiKeyDir != null) [
                "--api-key-file /var/lib/llama-cpp-${name}/api-keys"
              ]
            );
            # The same hardening as the primary unit. A model may load with `load-mode mlock`, so the
            # MEMLOCK limit stays unlimited.
            DynamicUser = true;
            LimitMEMLOCK = "infinity";
            NoNewPrivileges = true;
            PrivateMounts = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ cfg.modelsDir ];
            Restart = "on-failure";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            StateDirectory = "llama-cpp-${name}";
            WorkingDirectory = "/var/lib/llama-cpp-${name}";
          };

          # Assemble the per-key files under `apiKeyDir` into this router's own state directory. It
          # mirrors the primary unit's `preStart`: it strips a comment and an empty line, and it adds
          # a trailing newline.
          preStart = lib.mkIf (r.apiKeyDir != null) ''
            : > /var/lib/llama-cpp-${name}/api-keys
            for f in ${r.apiKeyDir}/*; do
              [ -f "$f" ] || continue
              ${lib.getExe' pkgs.gnused "sed"} -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$f" >> /var/lib/llama-cpp-${name}/api-keys
              printf '\n' >> /var/lib/llama-cpp-${name}/api-keys
            done
          '';
        }
      ) enabledRouters;

      # The global download environment, by mode. It applies to every model download.
      modeEnv =
        if cfg.download.mode == "slow" then
          {
            HF_XET_HIGH_PERFORMANCE = "false";
            HF_HUB_DISABLE_XET = "true";
          }
        else
          # fast-polite: pin the concurrency to the configured value.
          {
            HF_DISABLE_TELEMETRY = "true";
            HF_XET_CLIENT_ENABLE_ADAPTIVE_CONCURRENCY = "false";
            HF_XET_FIXED_DOWNLOAD_CONCURRENCY = toString cfg.download.xetConcurrency;
            HF_XET_DATA_MAX_CONCURRENT_FILE_DOWNLOADS = "1";
            HF_XET_NUM_CONCURRENT_RANGE_GETS = toString cfg.download.xetConcurrency;
            HF_XET_CLIENT_MAX_IDLE_CONNECTIONS = "2";
          };

      # One download command plus one status line per model. The steps run in sequence.
      #
      # A model downloads either one file (`download.glob == null`) or a shard set (a glob, through
      # `--include`, so every shard lands on disk). In both cases `llama-server` serves `hfFile` and
      # it finds a sibling shard next to it.
      downloadStep =
        name: m:
        let
          dir = "${cfg.modelsDir}/${m.hfRepo}";
          # A glob always re-runs the download, because the tool skips a shard it already holds. The
          # "already present" fast path applies to a plain single-file download only.
          alwaysDownload = m.download.glob != null;
          fileArgs =
            if m.download.glob != null then
              "--include ${builtins.toJSON m.download.glob} --local-dir ${dir}"
            else
              ''"${m.hfFile}" --local-dir ${dir}'';
          shown = if m.download.glob != null then m.download.glob else m.hfFile;
          # The download tool keeps its own metadata under <repo>/.cache/huggingface/download. When
          # `hfFile` names a shard and `download.minBytes` holds a value, delete an incomplete target
          # and its etag metadata, so a repair download really runs.
          repair = m.download.minBytes != null;
          repairCmd = ''
            if [ -f "$target" ] && [ "$(stat -c%s "$target")" -lt ${toString m.download.minBytes} ]; then
              echo "[${name}] removing incomplete stub ($(stat -c%s "$target") B < ${toString m.download.minBytes} B)"
              rm -f "$target" ${dir}/.cache/huggingface/download/${m.hfFile}.metadata ${dir}/.cache/huggingface/download/${m.hfFile}.lock
            fi
          '';
        in
        ''
          target=${modelFile name}
          ${lib.optionalString repair repairCmd}
          if [ -f "$target" ] && [ "${toString m.download.force}" != "1" ] && [ "${toString alwaysDownload}" != "1" ]; then
            echo "[${name}] already present: $target"
          else
            echo "[${name}] downloading ${m.hfRepo}/${shown} (mode=${cfg.download.mode})"
            mkdir -p ${dir}
            ${lib.optionalString (modeEnv != { }) ''
              export ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${v}") modeEnv)}
            ''}
            ${hf} download ${m.hfRepo} ${fileArgs}
            if [ -f "$target" ]; then
              echo "[${name}] done: $target ($(du -sh "$target" | cut -f1))"
            else
              echo "[${name}] FAILED: expected file missing at $target" >&2
              exit 1
            fi
          fi
          # Make the model tree world-readable, so any user and the router's own DynamicUser read it:
          # 644 on a file, 755 on a directory. The download tool writes world-readable files, but a
          # persisted `modelsDir` may be root-only and block the traverse. This runs on both paths.
          chmod -R a+rX ${dir}
        '';

      # The download step of a speculative-decoding DRAFT model. It lands in the same layout, and it
      # never becomes a router model: it feeds `--model-draft` on its own model's preset section. So
      # it must download before its parent.
      draftStep =
        name:
        if !(cfg.models.${name}.draft.enable) then
          ""
        else
          let
            d = cfg.models.${name}.draft;
            dir = "${cfg.modelsDir}/${d.hfRepo}";
            target = draftFile name;
            shown = d.hfFile;
          in
          ''
            target=${target}
            if [ -f "$target" ]; then
              echo "[${name}] draft already present: $target"
            else
              echo "[${name}] downloading draft ${d.hfRepo}/${shown} (mode=${cfg.download.mode})"
              mkdir -p ${dir}
              ${lib.optionalString (modeEnv != { }) ''
                export ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${v}") modeEnv)}
              ''}
              ${hf} download ${d.hfRepo} ${shown} --local-dir ${dir}
              if [ -f "$target" ]; then
                echo "[${name}] draft done: $target ($(du -sh "$target" | cut -f1))"
              else
                echo "[${name}] draft FAILED: expected file missing at $target" >&2
                exit 1
              fi
            fi
            chmod -R a+rX ${dir}
          '';

      # The LAN gate needs all three consumer values. With any one of them null, the aspect serves
      # the loopback router alone and it opens no port.
      lanGateReady = cfg.domain != null && cfg.certs.certFile != null && cfg.certs.keyFile != null;

      routerSubmodule = {
        options.enable = lib.mkEnableOption "this llama-server router";

        options.port = lib.mkOption {
          type = lib.types.port;
          default = 39704;
          description = "Port this llama-server router listens on.";
        };

        options.threads = lib.mkOption {
          type = lib.types.int;
          default = 8;
          description = ''
            Compute thread count for this router (`--threads`). The primary router keeps the host's
            whole thread budget. An extra router defaults lower, so the primary keeps most of the
            physical cores.
          '';
        };

        options.modelsMax = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = ''
            How many of this router's models stay resident in RAM at once (`--models-max`). The
            default is 1: exactly one model, loaded on request, unloaded when a different model needs
            the slot. Raise it on a router that holds several small compatible models. Keep the
            primary router at 1, so the largest model is always alone.
          '';
        };

        options.apiKeyDir = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Directory of API-key files for this router (`--api-key-file`). It has the same layout as
            the primary `apiKeyDir`: one key per file, and a `preStart` strips a comment and an empty
            line and assembles the result into this router's own state directory. `null` makes this
            router need no key.
          '';
        };
      };

      modelSubmodule = {
        options.enable = lib.mkEnableOption "this model in the router server";

        options.mainRouter = lib.mkOption {
          type = lib.types.str;
          default = "main";
          description = ''
            Which router owns this model. `"main"` names the primary `services.llama-cpp` server on
            `server.port`. Any other value names the equal entry of `routers`. A model appears in
            exactly one router's preset INI.
          '';
        };

        options.aliases = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra names the router answers to for this model.";
        };

        options.hfRepo = lib.mkOption {
          type = lib.types.str;
          example = "some-owner/some-model-GGUF";
          description = "Model repository, in `owner/name` form.";
        };

        options.hfFile = lib.mkOption {
          type = lib.types.str;
          example = "some-model-Q4_K_M.gguf";
          description = ''
            The GGUF file that serves this model, or the first shard of a split model. It reaches
            `llama-server` as `-m`, and it is the presence marker of an unsplit download.
          '';
        };

        options.download.glob = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "UD-IQ3_XXS/some-model-UD-IQ3_XXS-*.gguf";
          description = ''
            Glob pattern, inside `hfRepo`, that the download fetches. `null` fetches `hfFile` alone.
            For a split model, name a pattern that matches every shard. `llama-server` still serves
            `hfFile`, and it finds each sibling shard on disk.

            A value here turns the "already present" fast skip off, so the download always runs. The
            download tool skips a shard it already holds complete.
          '';
        };

        options.download.minBytes = lib.mkOption {
          type = with lib.types; nullOr ints.positive;
          default = null;
          description = ''
            Minimum acceptable size of `hfFile`, in bytes. With a value here, a smaller target counts
            as an incomplete stub: the download step deletes the file and its etag metadata, then it
            fetches the file again. Use it for a split model, where an interrupted first shard would
            otherwise stay for ever, because the tool matches the stored etag and not the size.
          '';
        };

        options.download.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Include this model in the sequential download run. The unit never starts at boot; start
            it through `kdn-llm-download.target` or directly.

            The slot declares this option and never reads it. This aspect reads it.
          '';
        };

        options.download.force = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Run the download again even when the target file exists. Use it for a repair.";
        };

        # Per-model serving performance. Each key maps to one key of that model's preset section, and
        # the router expands it onto the model's child process. The defaults target CPU-only,
        # memory-bandwidth-bound inference: flash attention on, one parallel slot, mmap on, reasoning
        # off.
        options.perf.threads = lib.mkOption {
          type = with lib.types; nullOr ints.positive;
          default = null;
          description = ''
            Thread count for this model (`-t`). `null` falls back to `kdn.llm.local.defaultThreads`.

            Memory-bound inference slows down with more threads than physical cores, because the SMT
            siblings contend. So prefer the physical core count.
          '';
        };

        options.perf.flashAttention = lib.mkOption {
          type = lib.types.enum [
            "on"
            "off"
            "auto"
          ];
          default = "on";
          description = "Flash Attention mode for this model (`-fa`).";
        };

        options.perf.cpuRange = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          example = "1-31";
          description = ''
            CPU affinity range for this model's compute threads (`--cpu-range`). `null` keeps the
            default, so the scheduler picks any CPU.

            Set it when the host isolates CPUs, so llama pins its threads onto the isolated cores
            instead of the contended shared ones. It complements `cpuStrict`. Keep `threads` equal to
            the number of CPUs in the range.
          '';
        };

        options.perf.cpuStrict = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Bind each compute thread to one dedicated CPU (`--cpu-strict 1`), instead of a scheduler
            migration. Use it with `cpuRange` on isolated cores.
          '';
        };

        options.perf.contextSize = lib.mkOption {
          type = with lib.types; nullOr ints.positive;
          default = null;
          description = ''
            Prompt context size for this model (`-c`). `null` keeps the model default. Set it per
            model to match the KV-cache RAM budget.
          '';
        };

        options.perf.mmap = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Memory-map the model file, instead of a copy into the page cache.";
        };

        options.perf.loadMode = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          example = "mlock";
          description = ''
            Memory load mode for this model (`--load-mode`). It states how the mapped weights lock
            into RAM. `"mlock"` locks the pages, so memory pressure cannot evict the page cache. It
            needs an unlimited MEMLOCK limit, and the aspect sets one. `null` omits the flag.
          '';
        };

        options.perf.parallel = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Number of server slots for this model (`--parallel`). 1 wastes no KV cache.";
        };

        options.perf.reasoning = lib.mkOption {
          type = lib.types.enum [
            "on"
            "off"
            "auto"
          ];
          default = "off";
          description = ''
            Reasoning mode for this model (`-rea`). `off` skips the invisible thinking block, so a
            short query streams tokens at once. A caller still opts in per request through
            `chat_template_kwargs`, with no restart.
          '';
        };

        options.perf.specType = lib.mkOption {
          type = lib.types.str;
          default = "draft-dspark";
          description = ''
            Speculative decoding type for this model (`--spec-type`). It works with `draft.enable`,
            and it must match the draft model family. It is a runtime feature, so it needs no
            recompile.
          '';
        };

        options.perf.specDraftNMax = lib.mkOption {
          type = with lib.types; nullOr ints.positive;
          default = null;
          description = ''
            Maximum draft tokens per speculative step (`--spec-draft-n-max`). `null` keeps the llama
            default. A higher value lets the draft propose more tokens per step, and it costs draft
            time. On a memory-bound CPU host, too high is slower. The mean accepted length is a good
            feedback signal.
          '';
        };

        options.perf.specDraftPMin = lib.mkOption {
          type = with lib.types; nullOr float;
          default = null;
          description = ''
            Minimum speculative decoding probability, greedy (`--spec-draft-p-min`). `null` keeps the
            default. It matters in sampling and in warmup only.
          '';
        };

        options.perf.specDraftPrio = lib.mkOption {
          type = with lib.types; nullOr (ints.between 0 2);
          default = null;
          description = ''
            Priority class of the DRAFT process (`--spec-draft-prio`): 0 normal, 1 medium, 2 high. On
            a busy isolated-core host the draft can starve behind the main model, and 2 gives it the
            scheduling priority it needs.
          '';
        };

        # An optional speculative-decoding DRAFT model. It downloads through the same mechanism, and
        # it never becomes a router model: only `model-draft` in the parent's preset names it.
        options.draft.enable = lib.mkEnableOption "a speculative-decoding draft model for this model";

        options.draft.hfRepo = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Repository of the draft GGUF, in `owner/name` form.";
        };

        options.draft.hfFile = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "File name of the draft GGUF inside `draft.hfRepo`.";
        };
      };
    in
    {
      options.kdn.llm.local.modelsDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/kdn/llm/models";
        description = ''
          Base directory of the downloaded GGUF model files.

          The slot required this value and gave no default, so inclusion alone could not evaluate.
          The default here names a neutral system path. A consumer that persists the directory sets
          its own path, and it registers the directory with its own persistence machinery.
        '';
      };

      options.kdn.llm.local.defaultThreads = lib.mkOption {
        type = with lib.types; nullOr ints.positive;
        default = null;
        example = 16;
        description = ''
          Fallback thread count for a model that names no `perf.threads`. `null` writes no `threads`
          key at all, so `llama-server` picks its own count.

          A thread count is machine data, so the default omits the flag. The example shows the shape.
        '';
      };

      options.kdn.llm.local.server.host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          Address the router listens on. Keep it on the loopback: the LAN endpoint goes through
          Caddy.
        '';
      };

      options.kdn.llm.local.server.port = lib.mkOption {
        type = lib.types.port;
        default = 39703;
        description = "Port the router listens on.";
      };

      options.kdn.llm.local.routers = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule routerSubmodule);
        default = { };
        description = ''
          Extra llama-server routers, each one serving the models whose `mainRouter` matches its own
          name.

          A router selects its model set through `models.<name>.mainRouter`, so no model definition
          is ever copied and every `perf` value keeps one source of truth. The name `"main"` belongs
          to the primary server, and an entry with that name is ignored.
        '';
      };

      options.kdn.llm.local.package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.llama-cpp;
        defaultText = lib.literalExpression "pkgs.llama-cpp";
        description = "The llama.cpp package that supplies `llama-server`.";
      };

      # The LAN gate. All three values below come from the consumer, and all three must hold a value
      # before the Caddy vhost appears.
      options.kdn.llm.local.domain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "llm.example.invalid";
        description = ''
          Hostname of the Caddy vhost, and the common name of the certificate. `null` turns the whole
          LAN gate off, so the router stays on the loopback and no firewall port opens.
        '';
      };

      options.kdn.llm.local.certs.certFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to the PEM public certificate that Caddy serves TLS from.";
      };

      options.kdn.llm.local.certs.keyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to the matching PEM private key. The aspect passes it to Caddy through
          `LoadCredential`, so the unit reads it at run time and no store path holds it.
        '';
      };

      options.kdn.llm.local.certs.sans = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "llm.alt.example.invalid"
          "llm.vpn.example.invalid"
        ];
        description = ''
          Extra hostnames the leaf certificate carries, beyond `domain`. The one vhost answers to
          each of them, with the same certificate and key.
        '';
      };

      options.kdn.llm.local.certs.listenAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "192.0.2.10"
          "198.51.100.10"
        ];
        description = ''
          Addresses the Caddy vhost binds, one per network that a certificate hostname resolves on.
          An empty list binds the default interface only.

          The example names two documentation-range addresses, from RFC 5737.
        '';
      };

      options.kdn.llm.local.apiKeyDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Directory of API-key files for the primary router (`--api-key-file`). Each file under it
          holds exactly one key, and a comment line or an empty line is ignored. A `preStart`
          assembles every file into the one file the server reads. `null` makes the server need no
          key.

          The consumer wires the directory, for example from its own secret manager.
        '';
      };

      options.kdn.llm.local.compatProxy.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Put an OpenCode DSML compat proxy between Caddy and the router. It translates DeepSeek DSML
          and Qwen XML into OpenAI JSON, and it passes every other path through, so one instance
          fronts the whole self-routing server.

          DECISION TO REVISE: this is a feature toggle inside the aspect, not the aspect's own switch.
          The rule for this tree turns a sub-toggle into its own aspect. It stays an option here,
          because the Caddy vhost points at the proxy port unconditionally, so a separate aspect would
          have to reach back into this one. That needs a design decision, not a mechanical port.
        '';
      };

      options.kdn.llm.local.compatProxy.port = lib.mkOption {
        type = lib.types.port;
        default = 9530;
        description = "Loopback port the compat proxy listens on. Caddy targets it.";
      };

      # Global download behaviour, not per-model. Every enabled model downloads in sequence, with
      # this one mode.
      options.kdn.llm.local.download.mode = lib.mkOption {
        type = lib.types.enum [
          "slow"
          "fast-polite"
        ];
        default = "slow";
        description = ''
          How hard the models download. It is global.

          `"slow"` turns the Xet transfer off and falls back to plain HTTP. It is gentle on the
          network. `"fast-polite"` keeps Xet on and pins the concurrency low: no adaptive ramp, and a
          fixed low concurrency. It is faster than `"slow"` and much gentler than the Xet default.
        '';
      };

      options.kdn.llm.local.download.xetConcurrency = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = ''
          Target Xet download concurrency in `"fast-polite"` mode. A higher value is faster and
          harder on the network. A lower value is gentler.
        '';
      };

      options.kdn.llm.local.download.tokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a file that holds one download token, as plain text with no `KEY=` prefix. The
          consumer wires it, for example from its own secret manager. `null` downloads anonymously,
          under a rate limit.
        '';
      };

      options.kdn.llm.local.models = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule modelSubmodule);
        default = { };
        description = ''
          The models the router serves, keyed by name. An enabled model is served and downloaded.

          An empty set makes the router serve nothing, so inclusion alone starts one idle server.
        '';
      };

      config = {
        # The proxy's `ROUTER_<NAME>_*` environment round-trips through a lowercase slug. An
        # uppercase key slugs back to the original name only when that name is plain lowercase
        # alphanumeric. A hyphen, an underscore or an uppercase letter would not match the on-disk
        # router section.
        assertions = lib.mkIf (enabledRouters != { }) [
          {
            assertion = lib.all (name: lib.match "^[a-z0-9]+$" name != null) (
              builtins.attrNames enabledRouters
            );
            message =
              "kdn.llm.local.routers names must be lowercase alphanumeric "
              + "(no hyphen, no underscore, no upper case); got: "
              + lib.concatStringsSep ", " (builtins.attrNames enabledRouters);
          }
        ];

        # The primary router: one process, an on-demand model load, exactly one resident model. The
        # nixpkgs module maps `settings.*` onto the flags.
        services.llama-cpp = {
          enable = true;
          inherit (cfg) package;
          settings = {
            host = cfg.server.host;
            port = cfg.server.port;
            models-preset = presetIni "main";
            models-max = 1;
            # Keep the resident model loaded: -1 turns the idle-unload timer off. Router mode has no
            # per-model time to live, and an unload happens only when a queued request needs the
            # slot. The line is explicit, so a future router default cannot change the behaviour.
            sleep-idle-seconds = -1;
          }
          // lib.optionalAttrs (cfg.apiKeyDir != null) {
            api-key-file = "/var/lib/llama-cpp/api-keys";
          };
          openFirewall = false;
        };

        # One raw unit per extra router, each with its own preset INI, port and key file. Everything
        # folds into one `systemd.services` merge, so the partial definitions below coexist with no
        # whole-namespace clash.
        systemd.services = lib.mkMerge [
          routerUnits
          {
            # The router runs as a DynamicUser, and it must read the models.
            llama-cpp.serviceConfig.ReadWritePaths = [ cfg.modelsDir ];
            # Raise the mlock limit, so an mlocked model locks. systemd defaults MEMLOCK to 8 MiB,
            # and that fails every mlock of a large model.
            llama-cpp.serviceConfig.LimitMEMLOCK = "infinity";
            # Assemble the per-key files under `apiKeyDir` into one file in llama-cpp's own state
            # directory, which its DynamicUser can write. It strips a comment line and an empty line.
            # A newline goes after each file, so two keys never run together.
            llama-cpp.preStart = lib.mkIf (cfg.apiKeyDir != null) ''
              : > /var/lib/llama-cpp/api-keys
              for f in ${cfg.apiKeyDir}/*; do
                [ -f "$f" ] || continue
                ${lib.getExe' pkgs.gnused "sed"} -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$f" >> /var/lib/llama-cpp/api-keys
                printf '\n' >> /var/lib/llama-cpp/api-keys
              done
            '';
            # Hand the private key to Caddy at run time, so no store path holds it.
            caddy.serviceConfig.LoadCredential = lib.mkIf lanGateReady [
              "llm-key:${cfg.certs.keyFile}"
            ];
            # One loopback compat proxy in front of the router. It forwards the client's
            # `Authorization` header — the bearer key that `--api-key-file` validates — on the
            # streaming path too, and it passes every other path through. So one instance is enough.
            kdn-llm-proxy-lan = lib.mkIf cfg.compatProxy.enable {
              description = "OpenCode DSML compat proxy to the local router";
              wantedBy = [ "multi-user.target" ];
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];

              environment = routerProxyEnv // {
                UPSTREAM_URL = "http://127.0.0.1:${toString cfg.server.port}";
                PROXY_HOST = "127.0.0.1";
                PROXY_PORT = toString cfg.compatProxy.port;
                # The proxy reads `ROUTER_<NAME>_URL` and answers to every model id in
                # `ROUTER_<NAME>_MODELS` on that upstream. Anything else falls back to
                # `UPSTREAM_URL`. With no extra router, neither key appears and the behaviour is the
                # original single-router one.
                FORWARD_AUTHORIZATION = "true";
              };

              serviceConfig = {
                ExecStart = lib.getExe compatProxyPkg;
                Restart = "always";
                RestartSec = "5s";
                DynamicUser = true;
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectSystem = "strict";
                ProtectHome = true;
              };
            };
            # One sequential download service. It walks every model that asks for a download, one at
            # a time, it skips a model already present unless the model forces it, and it prints one
            # status line for each.
            kdn-llm-download = {
              description = "Download the enabled local models, one at a time";
              # A download runs after the network comes up, and it never touches
              # `multi-user.target`, so it blocks neither boot nor activation.
              wantedBy = lib.mkIf (downloadModels != { }) [ "kdn-llm-download.target" ];
              partOf = lib.mkIf (downloadModels != { }) [ "kdn-llm-download.target" ];
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];

              path = [
                pkgs.python3Packages.huggingface-hub
                pkgs.coreutils # du, cut
              ];

              serviceConfig = {
                Type = "oneshot";
                Restart = "on-failure";
                RestartSec = "10s";
                LoadCredential = lib.optional (cfg.download.tokenFile != null) "HF_TOKEN:${cfg.download.tokenFile}";
              };

              script = ''
                set -euo pipefail
                if [ -n "''${CREDENTIALS_DIRECTORY:-}" ] && [ -f "''${CREDENTIALS_DIRECTORY}/HF_TOKEN" ]; then
                  export HF_TOKEN="$(cat "''${CREDENTIALS_DIRECTORY}/HF_TOKEN")"
                fi
                # Every dependency first, so a draft model lands before its parent.
                ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _: draftStep name) downloadModels)}
                ${lib.concatStringsSep "\n" (lib.mapAttrsToList downloadStep downloadModels)}
                echo "all configured downloads complete"
              '';
            };
          }
        ];

        # The one LAN gate. Caddy terminates TLS with the consumer's own certificate, and it reverse
        # proxies to the loopback compat proxy, which passes through to the router.
        services.caddy = lib.mkIf lanGateReady {
          enable = true;
          virtualHosts.${cfg.domain} = {
            # Bind each network that a certificate hostname resolves on, and answer to every extra
            # hostname.
            listenAddresses = cfg.certs.listenAddresses;
            # The extra hostnames of this one vhost. The primary is the vhost key itself.
            serverAliases = lib.remove cfg.domain cfg.certs.sans;
            extraConfig = ''
              tls ${cfg.certs.certFile} {$CREDENTIALS_DIRECTORY}/llm-key
              reverse_proxy 127.0.0.1:${toString cfg.compatProxy.port}
            '';
          };
        };

        # Caddy is the one process that needs a port. The router and the proxy stay on the loopback.
        networking.firewall.allowedTCPPorts = lib.mkIf lanGateReady [
          80
          443
        ];

        systemd.targets.kdn-llm-download = {
          description = "Download the enabled local models";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
        };

        environment.systemPackages = [
          cfg.package
          pkgs.python3Packages.huggingface-hub
          (pkgs.writeShellApplication {
            name = "kdn-llm-status";
            runtimeInputs = [ pkgs.systemd ];
            text = ''
              echo "== llama-server (router) =="
              systemctl status llama-cpp --no-pager || true
              echo
              ${lib.optionalString cfg.compatProxy.enable ''
                echo "== loopback compat proxy =="
                systemctl status kdn-llm-proxy-lan --no-pager || true
                echo
              ''}
              ${lib.optionalString lanGateReady ''
                echo "== caddy =="
                systemctl status caddy --no-pager || true
                echo
              ''}
              echo "== download service =="
              systemctl status kdn-llm-download --no-pager || true
              echo
              echo "== recent download logs =="
              journalctl -u kdn-llm-download -n 40 --no-pager || true
            '';
          })
        ];
      };
    };
}

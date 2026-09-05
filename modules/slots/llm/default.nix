# Local LLM serving slot.
#
# Serves several local LLMs with `llama-server` (from llama.cpp) in **router
# mode**: a single server process owns one HTTP API and loads/unloads individual
# GGUFs on demand into RAM. `--models-max 1` keeps exactly one model resident at
# a time (the others stay on disk), preserving the llama-swap "one model at a
# time" behaviour without the separate swap process.
#
# The server listens on 127.0.0.1 only. A LAN-visible endpoint is exposed via a
# dedicated Caddy reverse proxy with a self-signed certificate, fronted by one
# OpenCode DSML compat-proxy instance (which also passes any non-chat path
# through to the server, so model listing and completion routing both work).
# Only TCP 80/443 (Caddy) is ever opened in the firewall; the llama-server and
# proxy stay bound to 127.0.0.1.
#
# This slot is STANDALONE. It must not reference or assign any option
# declared by modules/universal/ or modules/meta/ (no kdn.env.*, kdn.disks.*,
# kdnConfig, etc.). See .agents/rules/slots-standalone.md.
#
# The models directory path, LAN domain, certificate paths, and API-key file
# are required, default-less options. The consuming host provides them (and may
# register the models dir under its own persistence machinery).
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.llm.local;

  hf = lib.getExe pkgs.python3Packages.huggingface-hub;

  enabledModels = lib.filterAttrs (_: m: m.enable) cfg.models;

  # Absolute path of a downloaded model file within modelsDir:
  #   <modelsDir>/<hfRepo>/<hfFile>
  modelFile = name: let
    m = cfg.models.${name};
  in "${cfg.modelsDir}/${m.hfRepo}/${m.hfFile}";

  # Absolute path of a draft model file (same layout as a model file):
  #   <modelsDir>/<hfRepo>/<hfFile>
  draftFile = name: let
    d = cfg.models.${name}.draft;
  in "${cfg.modelsDir}/${d.hfRepo}/${d.hfFile}";

  # Render a per-model preset section. `version` and the per-model keys map
  # 1:1 to llama-server CLI flags (key = flag name minus leading dashes; the
  # router expands them onto that model's child process). Router-controlled
  # keys (host, port, api-key, alias routing) are never emitted here. Global
  # defaults are folded into every section rather than relying on a `[*]`
  # catch-all section, which some builds do not honour.
  # Common defaults: memory-bandwidth-bound CPU inference wants physical
  # threads only (-t 16 on a 16-core part), flash attention on, and a single
  # parallel slot so no KV cache is wasted on extra slots.
  presetSection = name: let
    m = cfg.models.${name};
    perf = m.perf;
    threads = if perf.threads != null then perf.threads else 16;
  in
    lib.concatLines (
      ([
          "[${name}]"
          "model = ${modelFile name}"
          "threads = ${toString threads}"
          "flash-attn = ${perf.flashAttention}"
        ]
        ++ lib.optionals (perf.cpuRange != null) [
          "cpu-range = ${perf.cpuRange}"
          "cpu-strict = ${if perf.cpuStrict then "1" else "0"}"
        ]
        ++ lib.optionals (perf.contextSize != null) [
          "ctx-size = ${toString perf.contextSize}"
        ]
        ++ lib.optionals (m.aliases != []) [
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
          "spec-draft-p-min = ${perf.specDraftPMin}"
        ]
        ++ lib.optionals (m.draft.enable && perf.specDraftPrio != null) [
          "spec-draft-prio = ${toString perf.specDraftPrio}"
        ]
      )
    );

  modelPresetIni = pkgs.writeText "models-preset.ini" (
    lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _: presetSection name) enabledModels)
  );

  # Global download env vars by mode, applied to every model download.
  modeEnv =
    if cfg.download.mode == "slow"
    then {
      HF_XET_HIGH_PERFORMANCE = "false";
      HF_HUB_DISABLE_XET = "true";
    }
    else
      # fast-polite: pin concurrency to the configurable value.
      {
        HF_DISABLE_TELEMETRY = "true";
        HF_XET_CLIENT_ENABLE_ADAPTIVE_CONCURRENCY = "false";
        HF_XET_FIXED_DOWNLOAD_CONCURRENCY = toString cfg.download.xetConcurrency;
        HF_XET_DATA_MAX_CONCURRENT_FILE_DOWNLOADS = "1";
        HF_XET_NUM_CONCURRENT_RANGE_GETS = toString cfg.download.xetConcurrency;
        HF_XET_CLIENT_MAX_IDLE_CONNECTIONS = "2";
      };

  # One download command + status line per enabled model, run sequentially.
  # A model downloads either a single file (m.download.glob == null,
  # downloaded directly) or a shard set (glob set, downloaded via --include
  # so all shards land on disk). In both cases llama-server serves m.hfFile
  # and auto-discovers sibling shards next to it.
  downloadStep = name: m: let
    dir = "${cfg.modelsDir}/${m.hfRepo}";
    # A glob always re-runs hf download (hf skips shards already present);
    # the "already present" fast-path only applies to a plain single-file
    # download.
    alwaysDownload = m.download.glob != null;
    # Arguments selecting what to fetch. A glob is passed via --include
    # (snapshot_download path); a single file is passed positionally.
    fileArgs =
      if m.download.glob != null
      then "--include ${builtins.toJSON m.download.glob} --local-dir ${dir}"
      else ''"${m.hfFile}" --local-dir ${dir}'';
    shown =
      if m.download.glob != null
      then m.download.glob
      else m.hfFile;
    # HF keeps agent/poison metadata under <repo>/.cache/huggingface/download.
    # When `hfFile` points at a shard and `download.minBytes` set, delete the
    # target (and its etag metadata) if it is an incomplete stub so a repair
    # re-download actually runs — otherwise HF sees the metadata and skips.
    repair = m.download.minBytes != null;
    repairCmd = ''
      if [ -f "$target" ] && [ "$(stat -c%s "$target")" -lt ${toString m.download.minBytes} ]; then
        echo "[${name}] removing incomplete stub ($(stat -c%s "$target") B < ${toString m.download.minBytes} B)"
        rm -f "$target" ${dir}/.cache/huggingface/download/${m.hfFile}.metadata ${dir}/.cache/huggingface/download/${m.hfFile}.lock
      fi
    '';
  in ''
    target=${modelFile name}
    ${lib.optionalString (repair) repairCmd}
    if [ -f "$target" ] && [ "${toString m.download.force}" != "1" ] && [ "${toString alwaysDownload}" != "1" ]; then
      echo "[${name}] already present: $target"
    else
      echo "[${name}] downloading ${m.hfRepo}/${shown} (mode=${cfg.download.mode})"
      mkdir -p ${dir}
      ${lib.optionalString (modeEnv != {}) ''
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
    # Make the model tree world-readable so any user (and the
    # llama-cpp router DynamicUser) can read it: 644 on files, 755 on dirs.
    # HF downloads world-readable files but a persisted modelsDir may be
    # root:root 0750, blocking traverse. Runs on both the fresh-download
    # and already-present paths.
    chmod -R a+rX ${dir}
  '';

  # Download step for a speculative-decoding DRAFT model. It is fetched into
  # the same modelsDir layout (<repo>/<file>) but is never registered as a
  # router model — it only feeds `--model-draft` on its main model's preset
  # section, so it must download before/with its parent. Reuses the standard
  # single-file download path (positional file + local-dir).
  draftStep = name:
    if !(cfg.models.${name}.draft.enable)
    then ""
    else let
      d = cfg.models.${name}.draft;
      dir = "${cfg.modelsDir}/${d.hfRepo}";
      target = draftFile name;
      shown = d.hfFile;
    in ''
      target=${target}
      if [ -f "$target" ]; then
        echo "[${name}] draft already present: $target"
      else
        echo "[${name}] downloading draft ${d.hfRepo}/${shown} (mode=${cfg.download.mode})"
        mkdir -p ${dir}
        ${lib.optionalString (modeEnv != {}) ''
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
in {
  options.kdn.llm.local = {
    enable = lib.mkEnableOption "local LLM serving via llama-server router mode";

    modelsDir = lib.mkOption {
      type = lib.types.str;
      example = "/var/lib/kdn/llms/models";
      description = ''
        Base directory for downloaded GGUF model files. Required and has no
        default so the slot stays standalone: the consuming host supplies the
        path.
      '';
    };

    server.host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address the router llama-server listens on. Keep on loopback; the LAN endpoint goes through Caddy.";
    };
    server.port = lib.mkOption {
      type = lib.types.port;
      default = 39703;
      description = "Port the router llama-server listens on.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-cpp;
      description = "llama.cpp package providing llama-server.";
    };

    # LAN exposure: a self-signed-certificate Caddy vhost in front of one
    # compat-proxy in front of the loopback llama-server. None of these have a
    # default: the host owns the cert paths and the API-key file.
    domain = lib.mkOption {
      type = lib.types.str;
      example = "brys.lan.etra.net.int.kdn.im";
      description = "Public hostname of the Caddy vhost (also the cert CN/SAN).";
    };
    certs.certFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the PEM public certificate Caddy serves TLS from.";
    };
    certs.keyFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the corresponding PEM private key for Caddy.";
    };
    # Extra domain names the leaf cert carries (beyond `domain`). The Caddy
    # vhost listens on `domain` and each additional SAN's hostname, all served
    # by the same cert/key.
    certs.sans = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [
        "brys.lan.drek.net.int.kdn.im"
        "brys.priv.nb.net.int.kdn.im"
      ];
      description = "Additional hostnames the Caddy cert covers (SANs).";
    };
    # Addresses/interfaces the Caddy vhost binds, one per SAN-facing network
    # (e.g. each VLAN/interface a SAN hostname resolves on). Empty binds on the
    # default interface only.
    certs.listenAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [
        "192.168.41.31"
        "100.79.164.36"
      ];
      description = "Addresses the Caddy vhost listens on (one per SAN interface).";
    };
    apiKeyDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Directory of API-key files for the router llama-server
        (--api-key-file). Each file under it holds exactly one key; comment
        lines (starting with #) and empty lines are ignored. The host wires this
        (e.g. via sops-nix to /run/configs/llms/llama-server/api-keys/, where
        each sops key under it decrypts to one file). A prestart step assembles
        all files into a single file the server actually reads. When null, the
        server requires no key.
      '';
    };
    compatProxy.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Put an OpenCode DSML compat-proxy between Caddy and the llama-server.
        It translates DeepSeek DSML / Qwen XML into OpenAI JSON and also passes
        every other path through, so one instance fronts the self-routing
        server.
      '';
    };
    compatProxy.port = lib.mkOption {
      type = lib.types.port;
      default = 9530;
      description = "Loopback port the compat-proxy listens on (targeted by Caddy).";
    };

    # Global (not per-model) download behaviour. All enabled models download
    # sequentially with the same mode.
    download.mode = lib.mkOption {
      type = lib.types.enum [
        "slow"
        "fast-polite"
      ];
      default = "slow";
      description = ''
        How aggressively the enabled models download. Global for all models.
        - "slow" (default): disable Xet entirely and fall back to regular HTTP
          transfer. Gentle on the network.
        - "fast-polite": keep Xet enabled but pin concurrency low (disable
          adaptive ramping, fixed low concurrency). Faster than "slow", far
          gentler than Xet's default "fast".
      '';
    };
    download.xetConcurrency = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = ''
        Target Xet download concurrency used in "fast-polite" mode (the value
        of HF_XET_FIXED_DOWNLOAD_CONCURRENCY / HF_XET_NUM_CONCURRENT_RANGE_GETS).
        Higher = faster but more aggressive on the network. Lower = gentler.
      '';
    };
    download.tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing a HuggingFace token (HF_TOKEN). Plain token
        text, no KEY= line. The host wires this (e.g. via sops-nix to
        /run/configs/llms/huggingface/token). When null, downloads run
        anonymously (rate-limited).
      '';
    };

    models = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          {lib, ...}: {
            options.enable = lib.mkEnableOption "load this model in the router server";
            options.aliases = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Extra names the router server answers to for this model.";
            };
            options.hfRepo = lib.mkOption {
              type = lib.types.str;
              description = "HuggingFace repository, formatted owner/name.";
            };
            options.hfFile = lib.mkOption {
              type = lib.types.str;
              description = ''
                GGUF file path serving this model ("first" shard for a split
                model). Passed to llama-server (-m) and used as the presence
                marker for unsplit downloads.
              '';
            };
            options.download.glob = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Glob pattern (within hfRepo) that the download fetches. Defaults
                to the literal hfFile. For split models, set to a pattern that
                matches every shard, e.g.
                "UD-IQ3_XXS/DeepSeek-V4-Flash-UD-IQ3_XXS-*.gguf". llama-server
                still serves hfFile and auto-discovers sibling shards on disk.
                When set, the "already present" fast-skip is disabled and the
                download always runs (hf skips shards it already has complete).
              '';
            };
            options.download.minBytes = lib.mkOption {
              type = with lib.types; nullOr ints.positive;
              default = null;
              description = ''
                Minimum acceptable size in bytes for hfFile. When set and the
                target file is smaller than this, the download step treats it as
                an incomplete stub: it deletes the file and its HF agent etag
                metadata (.cache/huggingface/download/<file>.metadata) before
                re-downloading. Use for split models where an interrupted first
                shard may otherwise be skipped forever because HF matches the
                stored etag, not the file size. Omit to keep whatever is on disk.
              '';
            };
            options.download.enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "include this model in the sequential download run. The unit is NOT auto-started at boot; run it via kdn-llm-download.target or directly.";
            };
            options.download.force = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "re-run hf download even when the target file already exists (repair).";
            };
            # Per-model serving performance. These map to keys in that model's
            # preset INI section, which the router expands onto the model's
            # child process. Defaults target CPU-only memory-bandwidth-bound
            # inference on a ~16-core part: physical threads only, flash
            # attention on, a single parallel slot, mmap on, reasoning off.
            options.perf.threads = lib.mkOption {
              type = with lib.types; nullOr ints.positive;
              default = null;
              description = ''
                llama-server thread count for this model (-t). null uses the
                slot default of 16 (physical cores). Memory-bound inference
                slows with more threads than physical cores (SMT contention),
                so prefer 16 on a 5950X rather than 32.
              '';
            };
            options.perf.flashAttention = lib.mkOption {
              type = lib.types.enum ["on" "off" "auto"];
              default = "on";
              description = "Flash Attention mode for this model (-fa).";
            };
            options.perf.cpuRange = lib.mkOption {
              type = with lib.types; nullOr str;
              default = null;
              description = ''
                llama-server CPU affinity range for this model's compute
                threads (-Cr / --cpu-range, e.g. "1-31"). NULL leaves the
                default (no range, scheduler picks any CPU). Set this when the
                host isolates CPUs (isolcpus/nohz_full) so llama pins its
                threads onto the isolated cores instead of scattering to
                contended shared cpus. Complements `--cpu-strict 1`. Use
                together with `threads` matching the number of cpus in range.
              '';
            };
            options.perf.cpuStrict = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Bind each compute thread to a dedicated CPU (--cpu-strict 1) instead of letting the scheduler migrate. Use with `cpuRange` on isolated cores.";
            };
            options.perf.contextSize = lib.mkOption {
              type = with lib.types; nullOr ints.positive;
              default = null;
              description = ''
                Prompt context size (-c) for this model. NULL lets llama-server
                use the model default. Set per model to match KV-cache RAM
                budget (e.g. DeepSeek 65536, Qwen3-MoE 131072).
              '';
            };
            options.perf.mmap = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "memory-map the model file (mmap) instead of copying it into RAM page-cache.";
            };
            options.perf.parallel = lib.mkOption {
              type = lib.types.int;
              default = 1;
              description = "number of server slots for this model (-np / --parallel). 1 wastes no KV cache on extra slots.";
            };
            options.perf.reasoning = lib.mkOption {
              type = lib.types.enum ["on" "off" "auto"];
              default = "off";
              description = ''
                Reasoning/thinking mode for this model (-rea). `off` skips the
                invisible thinking block so short queries stream tokens
                immediately (biggest apparent speedup on reasoning models).
                Callers can still opt in per request via chat_template_kwargs
                (enable_thinking / reasoning_effort) without a restart.
              '';
            };
            options.perf.specType = lib.mkOption {
              type = lib.types.str;
              default = "draft-dspark";
              description = ''
                Speculative decoding type for this model (--spec-type). Used
                with `draft.enable`; must match the draft model family (e.g.
                `draft-dspark` for the DeepSeek V4 Flash DSpark drafter).
                Purely a runtime feature; needs no recompile.
              '';
            };
            options.perf.specDraftNMax = lib.mkOption {
              type = with lib.types; nullOr ints.positive;
              default = null;
              description = ''
                Max draft tokens per speculative step (--spec-draft-n-max).
                Null lets llama use its default (3). Higher means the draft can
                propose more tokens per step but costs draft time; on a
                memory-bound CPU host, too high can be slower. Mean accepted
                length is a good feedback signal to set this (mean len ≈ n).
              '';
            };
            options.perf.specDraftPMin = lib.mkOption {
              type = with lib.types; nullOr float;
              default = null;
              description = ''
                Min speculative decoding probability, greedy (--spec-draft-p-min).
                Null uses default (0.00). Only matters in sampling/warmup;
                leave null unless p-min threshold tuning is intended.
              '';
            };
            options.perf.specDraftPrio = lib.mkOption {
              type = with lib.types; nullOr (ints.between 0 2);
              default = null;
              description = ''
                Priority class for the DRAFT model process/threads
                (--spec-draft-prio). 0=normal, 1=medium, 2=high. On a busy
                isolated-core host the draft can starve behind the 15-thread
                main model; 2 gives it scheduling priority so it keeps up with
                speculative decoding.
              '';
            };
            # Optional speculative-decoding DRAFT model feeding this model.
            # It downloads through the same mechanism but is NOT registered as
            # a router model — only referenced via `model-draft` in this model's
            # preset section.
            options.draft.enable = lib.mkEnableOption "download and use a speculative-decoding draft model for this model";
            options.draft.hfRepo = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "HuggingFace repo of the draft GGUF (owner/name).";
            };
            options.draft.hfFile = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "GGUF file name of the draft within hfRepo.";
            };
          }
        )
      );
      default = {};
      description = "LLM models to serve via the router llama-server. Only enabled models are served and downloaded.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixos = {pkgs, ...}: {
      # The router server: one process, on-demand model load, exactly one
      # resident at a time (models-max=1). API-key enforced from a host-wired
      # file. Uses nixpkgs' services.llama-cpp mapping settings.* to flags.
      services.llama-cpp = {
        enable = true;
        inherit (cfg) package;
        settings =
          {
            host = cfg.server.host;
            port = cfg.server.port;
            models-preset = modelPresetIni;
            models-max = 1;
            # Keep the resident model loaded indefinitely: -1 disables the
            # idle-unload timer entirely (there is no per-model ttl in router
            # mode; unloading only happens when a queued request needs the
            # models-max slot). Set explicitly so future router defaults
            # cannot change this behaviour.
            sleep-idle-seconds = -1;
          }
          // lib.optionalAttrs (cfg.apiKeyDir != null) {
            api-key-file = "/var/lib/llama-cpp/api-keys";
          };
        openFirewall = false;
      };

      # The router runs as a DynamicUser and must read the models.
      systemd.services.llama-cpp.serviceConfig.ReadWritePaths = [
        cfg.modelsDir
      ];

      # Assemble the per-key files under apiKeyDir into a single file in
      # llama-cpp's StateDirectory (writable by its DynamicUser), stripping
      # comment (#) and empty lines. llama-server's --api-key-file reads the
      # assembled file. A guaranteed newline is appended after each file so keys
      # never run together if a source file lacks a trailing newline.
      systemd.services.llama-cpp.preStart = lib.mkIf (cfg.apiKeyDir != null) ''
        : > /var/lib/llama-cpp/api-keys
        for f in ${cfg.apiKeyDir}/*; do
          [ -f "$f" ] || continue
          ${lib.getExe' pkgs.gnused "sed"} -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$f" >> /var/lib/llama-cpp/api-keys
          printf '\n' >> /var/lib/llama-cpp/api-keys
        done
      '';

      # The single LAN gate: Caddy terminates TLS with the host-supplied
      # self-signed cert and reverse-proxies to the loopback compat-proxy
      # (which passes through to the llama-server). Hard-coded 80/443 only.
      services.caddy = {
        enable = true;
        virtualHosts.${cfg.domain} = {
          # Bind each SAN-facing interface/address (so the cert's domains all
          # answer), plus serve every SAN hostname.
          listenAddresses = cfg.certs.listenAddresses;
          # Extra hostnames the same vhost answers to; never the primary (that's
          # the vhost key itself).
          serverAliases = lib.remove cfg.domain cfg.certs.sans;
          extraConfig = ''
            tls ${cfg.certs.certFile} {$CREDENTIALS_DIRECTORY}/llm-key
            reverse_proxy 127.0.0.1:${toString cfg.compatProxy.port}
          '';
        };
      };

      # Inject the raw-decrypted leaf private key into Caddy at runtime. systemd
      # copies /run/secrets/.../llm.key into the unit's private credential dir
      # (visible only to the unit), never a world-readable static path.
      systemd.services.caddy.serviceConfig.LoadCredential = [
        "llm-key:${cfg.certs.keyFile}"
      ];

      networking.firewall.allowedTCPPorts = [
        80
        443
      ];

      # One loopback compat-proxy in front of the router server. It forwards
      # the client's Authorization header (the Bearer key that llama-server's
      # --api-key-file validates) on the streaming path too, and passes every
      # other path through, so a single instance is enough for the router.
      systemd.services."kdn-llm-proxy-lan" = lib.mkIf cfg.compatProxy.enable {
        description = "OpenCode DSML compat proxy → local router llama-server";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];

        environment = {
          UPSTREAM_URL = "http://127.0.0.1:${toString cfg.server.port}";
          PROXY_HOST = "127.0.0.1";
          PROXY_PORT = toString cfg.compatProxy.port;
          # llama-server authenticates the client's Bearer key; forward it on
          # the streaming path too.
          FORWARD_AUTHORIZATION = "true";
        };

        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.kdn.opencode-compat-proxy}";
          Restart = "always";
          RestartSec = "5s";
          DynamicUser = true;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
        };
      };

      # A single sequential download service. It walks all enabled models one
      # at a time, downloads each (skipping ones already present, unless
      # forced), and logs a status line after each. Downloads run directly in
      # the host network namespace; `download.mode` controls how aggressively
      # HF transfers (env-based concurrency capping). No netns / NAT / tc.
      systemd.services."kdn-llm-download" = {
        description = "Download enabled local LLM models, one at a time";
        # Downloads run only once the network is up, and never touch
        # multi-user.target. Started by (wantedBy) network-online.target,
        # after it, so they never block boot or activation.
        wantedBy = lib.mkIf (enabledModels != {}) ["kdn-llm-download.target"];
        partOf = lib.mkIf (enabledModels != {}) ["kdn-llm-download.target"];
        wants = ["network-online.target"];
        after = ["network-online.target"];

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
          # Dependencies (draft models) first, then the main models.
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _: draftStep name) enabledModels)}
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: m: downloadStep name m) enabledModels)}
          echo "all configured downloads complete"
        '';
      };

      systemd.targets."kdn-llm-download" = {
        description = "Download enabled local LLM models";
        after = ["network-online.target"];
        wants = ["network-online.target"];
      };

      environment.systemPackages = [
        cfg.package
        pkgs.python3Packages.huggingface-hub
        (pkgs.writeShellApplication {
          name = "kdn-llm-status";
          runtimeInputs = [pkgs.systemd];
          text = ''
            echo "== llama-server (router) =="
            systemctl status llama-cpp --no-pager || true
            echo
            ${lib.optionalString cfg.compatProxy.enable ''
              echo "== loopback compat-proxy =="
              systemctl status kdn-llm-proxy-lan --no-pager || true
              echo
            ''}
            echo "== caddy =="
            systemctl status caddy --no-pager || true
            echo
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

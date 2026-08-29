# Local LLM serving slot.
#
# Runs several local LLMs behind `llama-swap`, which spawns a `llama-server`
# (from llama.cpp) on demand and gives one OpenAI-compatible HTTP API.
# One model runs at a time; the others stay on disk.
#
# This slot is STANDALONE. It must not reference or assign any option
# declared by modules/universal/ or modules/meta/ (no kdn.env.*, kdn.disks.*,
# kdnConfig, etc.). See .agents/rules/slots-standalone.md.
#
# The models directory path is a required, default-less option. The consuming
# host provides it (and may register it under its own persistence machinery).
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.llm.local;

  hf = lib.getExe pkgs.python3Packages.huggingface-hub;

  enabledModels = lib.filterAttrs (_: m: m.enable) cfg.models;

  # Relative path of a downloaded model file within modelsDir:
  #   <modelsDir>/<hfRepo>/<hfFile>
  modelFile =
    name:
    let
      m = cfg.models.${name};
    in
    "${cfg.modelsDir}/${m.hfRepo}/${m.hfFile}";
in
{
  options.kdn.llm.local = {
    enable = lib.mkEnableOption "local LLM serving via llama-swap";

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
      description = "Address llama-swap listens on.";
    };
    server.port = lib.mkOption {
      type = lib.types.port;
      default = 39703;
      description = "Port llama-swap listens on.";
    };
    server.healthCheckTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = ''
        Seconds llama-swap waits for a model to become ready before considering
        it failed. Multi-hundred-GB models on CPU can take several minutes to
        load, so the llama-swap default (~120s) is too short.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-swap;
      description = "llama-swap package to use.";
    };
    llamaCppPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-cpp;
      description = "llama.cpp package providing llama-server.";
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
          { lib, ... }:
          {
            options.enable = lib.mkEnableOption "load this model in llama-swap";
            options.aliases = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "llama-swap aliases for this model name.";
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
            options.threads = lib.mkOption {
              type = with lib.types; nullOr ints.positive;
              default = null;
              description = "llama-server thread count (-t). null lets llama-server choose.";
            };
            options.ttl = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 3600;
              description = ''
                Seconds llama-swap keeps this model loaded after its last
                request before unloading it (model `ttl`). Default 1 hour.
                Large slow-to-load models (e.g. deepseek-v4-flash) may want far
                longer — set per model, e.g. 86400 (24h).
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
          }
        )
      );
      default = { };
      description = "LLM models to expose via llama-swap. Only enabled models are loaded.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixos =
      {
        lib,
        ...
      }:
      let
        toSwapModel = name: m: {
          cmd = ''
            ${lib.getExe' cfg.llamaCppPackage "llama-server"} --port ''${PORT} -m ${modelFile name} ${
              lib.escapeShellArgs (
                lib.optionals (m.threads != null) [
                  "-t"
                  (toString m.threads)
                ]
              )
            }
          '';
          aliases = m.aliases;
          ttl = m.ttl;
        };

        # Global download env vars by mode, applied to every model download.
        modeEnv =
          if cfg.download.mode == "slow" then
            {
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
        # so all shards land on disk). In both cases llama-swap serves m.hfFile
        # and llama-server auto-discovers sibling shards next to it.
        downloadStep =
          name: m:
          let
            dir = "${cfg.modelsDir}/${m.hfRepo}";
            # A glob always re-runs hf download (hf skips shards already
            # present); the "already present" fast-path only applies to a plain
            # single-file download.
            alwaysDownload = m.download.glob != null;
            # Arguments selecting what to fetch. A glob is passed via --include
            # (snapshot_download path); a single file is passed positionally.
            fileArgs =
              if m.download.glob != null then
                "--include ${builtins.toJSON m.download.glob} --local-dir ${dir}"
              else
                ''"${m.hfFile}" --local-dir ${dir}'';
            shown = if m.download.glob != null then m.download.glob else m.hfFile;
          in
          ''
            target=${modelFile name}
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
            # Make the model tree world-readable so any user (and the
            # llama-swap DynamicUser) can read it: 644 on files, 755 on dirs.
            # HF downloads world-readable files but a persisted modelsDir may be
            # root:root 0750, blocking traverse. Runs on both the fresh-download
            # and already-present paths.
            chmod -R a+rX ${dir}
          '';
      in
      {
        services.llama-swap = {
          enable = true;
          listenAddress = cfg.server.host;
          port = cfg.server.port;
          settings = {
            inherit (cfg.server) healthCheckTimeout;
            models = lib.mapAttrs toSwapModel enabledModels;
          };
        };

        # llama-swap runs as a DynamicUser and must be able to read the models.
        systemd.services.llama-swap.serviceConfig.ReadWritePaths = [
          cfg.modelsDir
        ];

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
          wantedBy = lib.mkIf (enabledModels != { }) [ "kdn-llm-download.target" ];
          partOf = lib.mkIf (enabledModels != { }) [ "kdn-llm-download.target" ];
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
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: m: downloadStep name m) enabledModels)}
            echo "all configured downloads complete"
          '';
        };

        systemd.targets."kdn-llm-download" = {
          description = "Download enabled local LLM models";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
        };

        environment.systemPackages = [
          cfg.llamaCppPackage
          pkgs.python3Packages.huggingface-hub
          (pkgs.writeShellApplication {
            name = "kdn-llm-status";
            runtimeInputs = [ pkgs.systemd ];
            text = ''
              echo "== llama-swap =="
              systemctl status llama-swap --no-pager || true
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

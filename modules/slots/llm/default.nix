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

  # The router-server INI preset: one `[<name>]` section per enabled model. The
  # section name becomes the model id the API answers to; `model` is the absolute
  # GGUF path; `alias`/`threads` map to llama-server flags. Only `model` is
  # always present. See common/preset.cpp (load_from_ini) + server-models.cpp.
  modelPresetIni = pkgs.writeText "models-preset.ini" (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: m:
          lib.concatLines (
            [
              "[${name}]"
              "model = ${modelFile name}"
            ]
            ++ lib.optionals (m.aliases != []) [
              "alias = ${lib.concatStringsSep "," m.aliases}"
            ]
            ++ lib.optionals (m.threads != null) [
              "threads = ${toString m.threads}"
            ]
          )
      )
      enabledModels
    )
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
  in ''
    target=${modelFile name}
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
    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file with API keys for the router llama-server
        (--api-key-file). Each key on its own line; lines starting with # are
        comments. When null, the server requires no key. The host wires this
        (e.g. via sops-nix to /run/configs/brys/llms/api-keys). Treated as a
        file the DynamicUser can read.
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
            options.threads = lib.mkOption {
              type = with lib.types; nullOr ints.positive;
              default = null;
              description = "llama-server thread count (-t). null lets llama-server choose.";
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
          // lib.optionalAttrs (cfg.apiKeyFile != null) {
            api-key-file = cfg.apiKeyFile;
          };
        openFirewall = false;
      };

      # The router runs as a DynamicUser and must read the models.
      systemd.services.llama-cpp.serviceConfig.ReadWritePaths = [
        cfg.modelsDir
      ];

      # The single LAN gate: Caddy terminates TLS with the host-supplied
      # self-signed cert and reverse-proxies to the loopback compat-proxy
      # (which passes through to the llama-server). Hard-coded 80/443 only.
      services.caddy = {
        enable = true;
        virtualHosts.${cfg.domain}.extraConfig = ''
          tls ${cfg.certs.certFile} ${cfg.certs.keyFile}
          reverse_proxy 127.0.0.1:${toString cfg.compatProxy.port}
        '';
      };

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

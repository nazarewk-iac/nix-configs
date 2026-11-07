# LiteLLM gateway — a single OpenAI-compatible entrypoint for the local LLM fleet.
#
# Task: docs/tasks/2026-11/litellm-gateway/. Host-LOCAL module (like
# hosts/brys/llm.nix) because it is deployed only on etra.
#
# ## State: LIVE (2026-11-05)
#
# The container runs (`autoStart = true`) and reaches brys over the NetBird mesh:
# brys exposes llama-swap on `39704` via a narrow socat relay (hosts/brys/llm.nix,
# firewall-opened only on `nb-priv`), and `litellm-brys-egress` forwards to that
# mesh address. Verified end to end with a real completion.
#
# ## Why no database
#
# No Postgres (`DATABASE_URL` unset): no virtual keys, no budgets, no spend logs,
# one shared master key — which is what we want (research.md).
#
# ## Network shape (the repo's container rule: private network + narrow socat)
#
# The guest has a private veth (no host network). It reaches the outside ONLY
# through narrow host socat relays:
#   - ingress 0.0.0.0:4000       -> guest:4000   (clients -> gateway; the router
#                                                 firewall admits it only from nb-priv)
#   - egress  10.233.100.1:8443  -> brys netbird:39704 (gateway -> brys)
# The guest's api_base is http://10.233.100.1:8443/v1.
{ config, lib, pkgs, kdnConfig, ... }:
let
  hostAddress = "10.233.100.1";
  localAddress = "10.233.100.2";
  gatewayPort = 4000;
  egressPort = 8443;
  # brys over the NetBird mesh (nb-priv). Its llama-swap is exposed there on
  # 39704 by a narrow relay (hosts/brys/llm.nix); 39700 itself is loopback-only.
  brysHost = "100.79.164.36";
  brysPort = 39704;
  # oams over NetBird (nb-priv), same relay pattern on 39704.
  oamsHost = "100.79.80.79";
  oamsPort = 39704;
  oamsEgressPort = 8444;

  # --- Gateway config, GENERATED from data/llm.nix (no flat file to sync) -------
  #
  # Every alias on brys is one deployment. The aliases oams also serves get a
  # SECOND deployment (second host), so those model groups load-balance across
  # both and fail over. `litellm_settings`/`router_settings` carry the health
  # checks (#1) and the long-TTFT streaming timeouts (#6).
  data = import ../../data/llm.nix;
  llm = import ../../lib/llm.nix { inherit lib; };
  views = { brys = llm.mkMemberView data "brys"; oams = llm.mkMemberView data "oams"; };
  # Deployments: one per (host, alias). `api_base`/`api_key` are per-host env vars
  # the container resolves at start (see the container ExecStart).
  # Measured rates for a base model id on this host, or null.
  ratesOf = host: baseId: (views.${host}.models.${baseId}.capabilities.rates or null);
  deployments =
    host: baseEnv: keyEnv:
    map (
      alias:
      let
        baseId = views.${host}.aliasToModel.${alias};
        r = ratesOf host baseId;
      in
      {
        model_name = alias;
        litellm_params = {
          model = "openai/${baseId}";
          api_base = "os.environ/${baseEnv}";
          api_key = "os.environ/${keyEnv}";
        }
        # Measured throughput -> a tpm rate limit (decode t/s * 60 s, a loose ceiling
        # so latency-based/usage routing can use it; a busy host still refuses work).
        // lib.optionalAttrs (r != null) {
          tpm = builtins.floor (r.decode * 60);
          # (#4) Per-deployment streaming timeout = the first-token (prefill) wait for
          # a FULL context: servedContext / prefill_tokens_per_second, plus margin.
          # A deep model at 1M ctx and ~0.2 t/s prefill needs hours; a fast small
          # model needs seconds, so a dead one fails fast. Floor 120 s, no ceiling
          # (a slow-but-alive prefill MUST be allowed to finish).
          # Budget a FIRST TOKEN for at most 100k tokens of context (the policy:
          # never START a request above ~100k; a session may build past that via the
          # disk session cache / prefix reuse, not one huge cold prefill). Capped at
          # 2h so a dead-but-connected backend cannot hang a client for longer; a
          # genuinely running prefill resumes from checkpoints, not from scratch.
          stream_timeout = let
            prefill = if r.prefill <= 0 then 1 else r.prefill;
            startTokens = 100 * 1024;
            budget = 120 + builtins.floor (startTokens / prefill);
          in if budget > 7200 then 7200 else budget;
        };
        model_info = {
          id = "${host}-${alias}";
          # (#1) A cheap, SHORT probe: the egress relay to a blackholed host HANGS its
          # upstream connect for minutes, so the probe must time out fast (well under
          # health_check_interval) or the deployment never flips unhealthy.
          health_check_timeout = 5;
          health_check_max_tokens = 1;
        }
        // lib.optionalAttrs (r != null) {
          # Measured throughput, surfaced via /model/info for clients and docs.
          tokens_per_second = r.decode;
          prefill_tokens_per_second = r.prefill;
        };
      }
    ) (builtins.attrNames views.${host}.aliasToModel);

  # brys deployment for every alias; oams only for aliases it also serves.
  brysAliases = builtins.attrNames views.brys.aliasToModel;
  oamsAliases = builtins.attrNames views.oams.aliasToModel;

  modelList =
    (deployments "brys" "BRYS_API_BASE" "BRYS_API_KEY")
    ++ (deployments "oams" "OAMS_API_BASE" "OAMS_API_KEY");

  gatewayConfig = {
    model_list = modelList;
    litellm_settings = {
      callbacks = [ "prometheus" "probe.host_probe" ];
      drop_params = true;
      # (#6) a very long first token (huge prefill) must not be cut off. These are
      # the proxy-wide defaults; the per-deployment streaming limit is what governs
      # a live stream (time since the last chunk, not wall-clock total).
      request_timeout = 3600;
      # /metrics needs no bearer token (Prometheus scrape). `public_routes` alone is
      # NOT enough: /metrics is in the "requires auth despite public" list, and only
      # this flag disables it (litellm/proxy/auth/user_api_key_auth.py).
      require_auth_for_metrics_endpoint = false;
    };
    general_settings = {
      master_key = "os.environ/LITELLM_MASTER_KEY";
      # (#1) background health checks + routing: a blackholed host is filtered out
      # of the candidates BEFORE any connect, so a client request never pays a
      # connect timeout. Probe cheaply and detect fast.
      background_health_checks = true;
      health_check_interval = 30;
      health_check_staleness_threshold = 120;
      enable_health_check_routing = true;
      # /metrics carries no secrets (counters/latency) and is scraped by the
      # containerised Prometheus. `litellm_settings` sets the switch that makes it
      # unauthenticated (public_routes alone is overridden for /metrics).
      public_routes = [ "/metrics" ];
      # (#1) Durable routing state: the router's cooldown/usage/latency DualCache
      # uses this Redis via `coordination_redis` (router._update_redis_cache). A
      # local valkey/redis with AOF persists it across restarts; without it the
      # router is in-memory-per-worker and forgets on restart.
      coordination_redis = {
        host = hostAddress;
        port = 6379;
      };
    };
    router_settings = {
      timeout = 3600;
      # (#6) per-chunk idle limit for a live stream: allow a long gap for the first
      # token, but a genuinely silent backend still dies. Steady streaming is
      # unaffected once tokens flow.
      stream_timeout = 1800;
      num_retries = 1;
      cooldown_time = 30;
      allowed_fails = 2;
      routing_strategy = "simple-shuffle";
      enable_weighted_failover = true;
    };
  };
  # --- Optional Postgres for LiteLLM persistence (#3) --------------------------
  #
  # OFF by default. LiteLLM uses a DB for virtual keys, spend logs, budgets, and to
  # persist config-managed models — none required for routing. Enabling it needs a
  # working Prisma schema+query engine; on NixOS this means prisma-engines, whose
  # version must match the prisma pinned inside nixpkgs' litellm (see the task doc
  # for the exact compatibility note). `database.enable = true` wires it all.
  dbEnabled = false;
  dbUser = "litellm";
  dbName = "litellm";
  dbPasswordFile = "/var/lib/litellm/db-password";
  configFile = (pkgs.formats.json { }).generate "litellm-config.json" gatewayConfig;
in
{
  # State for the gateway. DB-less, so this is only logs / a local cache / the
  # generated master key, but it must survive a reboot (task requirement: a
  # persistence dataset before activation).
  kdn.disks.persist."sys/state".directories = [
    {
      directory = "/var/lib/litellm";
      mode = "0750";
    }
    # Prometheus TSDB (state, survives reboot). The prometheus container bind-mounts
    # it, and systemd-nspawn needs the host path to exist.
    {
      directory = "/var/lib/prometheus2";
      mode = "0750";
    }
    # Redis AOF for durable routing state (#1). systemd's redis `StateDirectory`
    # is /var/lib/redis-litellm; on this tmpfs-root host it must be persisted.
    {
      directory = "/var/lib/redis-litellm";
      mode = "0700";
    }
  ];
  # The container's writable root.
  kdn.disks.persist."sys/cache".directories = [
    {
      directory = "/var/lib/nixos-containers";
      mode = "0755";
    }
  ];

  containers.litellm = {
    autoStart = true;
    restartIfChanged = true;
    privateNetwork = true;
    inherit hostAddress localAddress;

    bindMounts."/etc/litellm/config.yaml" = {
      hostPath = "${configFile}";
      isReadOnly = true;
    };
    # The host-reachability callback, loaded from beside config.yaml (module
    # `probe`, instance `host_probe` — see litellm_settings.callbacks).
    bindMounts."/etc/litellm/probe.py" = {
      hostPath = "${./litellm_probe.py}";
      isReadOnly = true;
    };
    bindMounts."/var/lib/litellm" = {
      hostPath = "/var/lib/litellm";
      isReadOnly = false;
    };
    # The SOPS-decrypted secrets, as individual FILES mounted under /etc — NOT
    # under /run: the container has its own /run tmpfs which SHADOWS any bind placed
    # there (observed: /run/configs/llms was empty inside the guest).
    bindMounts."/etc/litellm-master-key" = {
      hostPath = "/run/configs/llms/litellm/master-key";
      isReadOnly = true;
    };
    bindMounts."/etc/litellm-llama-key" = {
      hostPath = "/run/configs/llms/llama-server/api-keys/default";
      isReadOnly = true;
    };

    config =
      { pkgs, ... }:
      {
        networking.firewall.allowedTCPPorts = [ gatewayPort ];

        # The master key is a SOPS secret (llms.nonsensitive: litellm.master-key),
        # mounted read-only into the container at /run/configs/llms. One key for the
        # gateway AND every client (Pi/OpenCode read the same path on their host).
        # (No auto-generation: a generated key would not match the clients'.)
        # Nothing to create here; the container reads it directly below.

        systemd.services.litellm = {
          description = "LiteLLM OpenAI-compatible gateway";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            ExecStart = ''
              ${pkgs.writeShellScript "litellm-run" ''
                set -eu
                export LITELLM_MASTER_KEY="$(cat /etc/litellm-master-key)"
                # The probe callback (probe.host_probe) lives beside config.yaml.
                export PYTHONPATH="/etc/litellm''${PYTHONPATH:+:$PYTHONPATH}"
                # Upstream is brys' llama-swap over NetBird, reached through the
                # host egress relay. Plain HTTP (no TLS to verify), real API key.
                export BRYS_API_BASE="http://${hostAddress}:${toString egressPort}/v1"
                export BRYS_API_KEY="$(cat /etc/litellm-llama-key)"
                export OAMS_API_BASE="http://${hostAddress}:${toString oamsEgressPort}/v1"
                # Same shared llama-server key as brys (one fleet api-key file).
                export OAMS_API_KEY="$(cat /etc/litellm-llama-key)"
                export PROMETHEUS_MULTIPROC_DIR=/var/lib/litellm/prom
                install -d -m 0750 "$PROMETHEUS_MULTIPROC_DIR"
                ${lib.optionalString dbEnabled ''
                # Prisma engines from nixpkgs (the packaged prisma has none).
                export PRISMA_SCHEMA_ENGINE_BINARY="${pkgs.prisma-engines}/bin/schema-engine"
                export PRISMA_QUERY_ENGINE_LIBRARY="${pkgs.prisma-engines}/lib/libquery_engine.so.node"
                export DATABASE_URL="postgresql://${dbUser}:$(cat ${dbPasswordFile})@${hostAddress}:5432/${dbName}"
                ''}
                exec ${pkgs.litellm}/bin/litellm \
                  --config /etc/litellm/config.yaml \
                  --host 0.0.0.0 --port ${toString gatewayPort}
              ''}
            '';
            Restart = "always";
            RestartSec = 5;
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };

        system.stateVersion = "26.05";
      };
  };

  # --- Durable routing state: Redis with AOF (#1) -----------------------------
  #
  # The router's DualCache (cooldowns, usage, latency history) uses Redis when
  # `general_settings.coordination_redis` is set. A local redis with append-only
  # persistence keeps that state across proxy restarts and shares it across workers.
  # Bound to loopback; a narrow relay exposes it on the litellm bridge only, so the
  # guest reaches it and nothing else does. Routing counters are not secrets.
  services.redis.servers.litellm = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
    appendOnly = true;
    appendFsync = "everysec";
  };

  systemd.services.litellm-redis-ingress = {
    description = "Expose the routing-state Redis to the LiteLLM container";
    wantedBy = [ "multi-user.target" ];
    after = [ "redis-litellm.service" ];
    wants = [ "redis-litellm.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:6379,bind=${hostAddress},fork,reuseaddr TCP:127.0.0.1:6379";
      Restart = "always";
      RestartSec = 3;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
    };
  };

  # The prober's health file must exist before the container bind-mounts the dir
  # (a file bind-mount would break on the prober's atomic rename; the dir mount is
  # safe, so we only guarantee the file is present at boot).
  systemd.tmpfiles.rules = [ "f /var/lib/litellm/host-health.json 0644 root root -" ];

  # --- Host-side reachability prober (#2) -------------------------------------
  #
  # Connects to each host's llama-swap over NetBird DIRECTLY (a real connect
  # timeout, unlike the relay path) and writes host-health.json for the container
  # callback to read. Only the two known hosts; extend the map as hosts join.
  systemd.services.litellm-host-probe = {
    description = "Probe brys/oams llama-swap reachability over NetBird";
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.coreutils pkgs.bash ];
    serviceConfig = {
      Type = "oneshot";
      # Cheap, idempotent writer driven by the timer below.
      StartLimitIntervalSec = 0;
      StartLimitBurst = 0;
    };
    script = ''
      set -eu
      f=/var/lib/litellm/host-health.json
      tmp="$f.tmp"
      probe() { if timeout 3 bash -c "exec 3<>/dev/tcp/$1/39704" 2>/dev/null; then printf true; else printf false; fi; }
      printf '{"brys": %s, "oams": %s}\n' "$(probe ${brysHost})" "$(probe ${oamsHost})" > "$tmp"
      mv "$tmp" "$f"
    '';
  };
  systemd.timers.litellm-host-probe = {
    description = "Recheck host reachability";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "15s";
    };
  };

  # --- Prometheus scraping the gateway's /metrics (#2) ------------------------
  #
  # A confined Prometheus (the prometheus-container aspect) scrapes the gateway.
  # The gateway's /metrics is on a public route (no bearer token), so the scrape is
  # unauthenticated and needs no key. Prometheus reaches the gateway over the
  # container bridge; the gateway stays on its own private veth.
  kdn.prometheus-container = {
    hostAddress = "10.233.101.1";
    localAddress = "10.233.101.2";
    stateDir = "/var/lib/prometheus2";
    # Served under /prometheus by etra's Caddy, which strips the prefix. The
    # external URL keeps absolute links on /prometheus; route-prefix `/` lets the
    # strip work.
    extraFlags = [
      "--web.external-url=https://etra.priv.nb.net.int.kdn.im/prometheus/"
      "--web.route-prefix=/"
    ];
    targets = [
      {
        job = "litellm";
        targets = [ "10.233.101.1:${toString gatewayPort}" ];  # unauthenticated /metrics (public_routes)
        interval = "15s";
        metricsPath = "/metrics/";  # trailing slash avoids the 307 to /metrics/
      }
    ];
  };

  # Host firewall on the container veth (the bridge is not trusted by nixos-fw).
  # `gatewayPort` lets the ingress relay reach the guest; `egressPort` lets the
  # guest reach the egress relay bound on the bridge address (without it the
  # backend calls are blackholed and every completion times out).
  # The prometheus container reaches the gateway ingress (0.0.0.0:4000 on the host)
  # through the host firewall; the veth is not trusted, so open just that port.
  networking.firewall.interfaces.ve-prometheus.allowedTCPPorts = [ gatewayPort ];

  networking.firewall.interfaces.ve-litellm.allowedTCPPorts = [
    gatewayPort
    egressPort
    oamsEgressPort
    6379  # routing-state Redis relay
  ];

  # Ingress relay: LAN clients -> guest gateway. It binds 0.0.0.0 so clients on
  # etra's trusted LAN (`nb-priv`, see hosts/etra/default.nix) reach it at
  # http://<etra>:4000; the router firewall drops it on every untrusted net.
  systemd.services.litellm-ingress = {
    description = "Relay :${toString gatewayPort} to the LiteLLM container";
    wantedBy = [ "multi-user.target" ];
    after = [ "container@litellm.service" ];
    wants = [ "container@litellm.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:${toString gatewayPort},bind=0.0.0.0,fork,reuseaddr TCP:${localAddress}:${toString gatewayPort}";
      Restart = "always";
      RestartSec = 3;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  # Egress relay: guest -> brys' mesh-exposed llama-swap (39704).
  systemd.services.litellm-brys-egress = {
    description = "Relay the LiteLLM container to brys:${toString brysPort}";
    wantedBy = [ "multi-user.target" ];
    after = [ "container@litellm.service" ];
    wants = [ "container@litellm.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:${toString egressPort},bind=${hostAddress},fork,reuseaddr,connect-timeout=5 TCP:${brysHost}:${toString brysPort}";
      Restart = "always";
      RestartSec = 3;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  systemd.services.litellm-oams-egress = {
    description = "Relay the LiteLLM container to oams:${toString oamsPort}";
    wantedBy = [ "multi-user.target" ];
    after = [ "container@litellm.service" ];
    wants = [ "container@litellm.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:${toString oamsEgressPort},bind=${hostAddress},fork,reuseaddr,connect-timeout=5 TCP:${oamsHost}:${toString oamsPort}";
      Restart = "always";
      RestartSec = 3;
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };
}

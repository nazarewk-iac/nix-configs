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
  deployments =
    host: baseEnv: keyEnv:
    map (alias: {
      model_name = alias;
      litellm_params = {
        model = "openai/${views.${host}.aliasToModel.${alias}}";
        api_base = "os.environ/${baseEnv}";
        api_key = "os.environ/${keyEnv}";
      };
      model_info.id = "${host}-${alias}";
    }) (builtins.attrNames views.${host}.aliasToModel);

  # brys deployment for every alias; oams only for aliases it also serves.
  brysAliases = builtins.attrNames views.brys.aliasToModel;
  oamsAliases = builtins.attrNames views.oams.aliasToModel;

  modelList =
    (deployments "brys" "BRYS_API_BASE" "BRYS_API_KEY")
    ++ (deployments "oams" "OAMS_API_BASE" "OAMS_API_KEY");

  gatewayConfig = {
    model_list = modelList;
    litellm_settings = {
      callbacks = [ "prometheus" ];
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
    bindMounts."/var/lib/litellm" = {
      hostPath = "/var/lib/litellm";
      isReadOnly = false;
    };
    # brys llama-swap requires an API key. It comes from the shared llms sops file
    # (config now mounts it on etra); bind just that one key into the guest.
    bindMounts."/run/secrets/brys-api-key" = {
      hostPath = "/run/configs/llms/llama-server/api-keys/default";
      isReadOnly = true;
    };

    config =
      { pkgs, ... }:
      {
        networking.firewall.allowedTCPPorts = [ gatewayPort ];

        # Generate the shared master key on first start (DB-less: one bearer key
        # for every client). It lives in the persisted state dir.
        systemd.services.litellm-keygen = {
          description = "Generate the LiteLLM master key once";
          wantedBy = [ "multi-user.target" ];
          before = [ "litellm.service" ];
          serviceConfig.Type = "oneshot";
          script = ''
            set -eu
            install -d -m 0750 /var/lib/litellm
            test -s /var/lib/litellm/master-key || \
              ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/litellm/master-key
            chmod 0400 /var/lib/litellm/master-key
          '';
        };

        systemd.services.litellm = {
          description = "LiteLLM OpenAI-compatible gateway";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network.target"
            "litellm-keygen.service"
          ];
          wants = [ "litellm-keygen.service" ];
          serviceConfig = {
            ExecStart = ''
              ${pkgs.writeShellScript "litellm-run" ''
                set -eu
                export LITELLM_MASTER_KEY="$(cat /var/lib/litellm/master-key)"
                # Upstream is brys' llama-swap over NetBird, reached through the
                # host egress relay. Plain HTTP (no TLS to verify), real API key.
                export BRYS_API_BASE="http://${hostAddress}:${toString egressPort}/v1"
                export BRYS_API_KEY="$(cat /run/secrets/brys-api-key)"
                export OAMS_API_BASE="http://${hostAddress}:${toString oamsEgressPort}/v1"
                # Same shared llama-server key as brys (one fleet api-key file).
                export OAMS_API_KEY="$(cat /run/secrets/brys-api-key)"
                export PROMETHEUS_MULTIPROC_DIR=/var/lib/litellm/prom
                install -d -m 0750 "$PROMETHEUS_MULTIPROC_DIR"
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

  # --- Prometheus scraping the gateway's /metrics (#2) ------------------------
  #
  # A confined Prometheus (the prometheus-container aspect) scrapes the gateway.
  # The gateway's /metrics needs the bearer master key, so the key is mounted into
  # the TSDB dir (readable by the prometheus user) and passed as the scrape auth.
  # Prometheus reaches the gateway through a narrow socat relay on the container
  # bridge; the gateway stays on its own private veth.
  kdn.prometheus-container = {
    hostAddress = "10.233.101.1";
    localAddress = "10.233.101.2";
    stateDir = "/var/lib/prometheus2";
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
      ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:${toString egressPort},bind=${hostAddress},fork,reuseaddr TCP:${brysHost}:${toString brysPort}";
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
      ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:${toString oamsEgressPort},bind=${hostAddress},fork,reuseaddr TCP:${oamsHost}:${toString oamsPort}";
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

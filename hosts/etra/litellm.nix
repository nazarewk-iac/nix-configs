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
{ lib, pkgs, kdnConfig, ... }:
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
      hostPath = "${kdnConfig.self}/hosts/etra/litellm.config.yaml";
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

  # Host firewall on the container veth (the bridge is not trusted by nixos-fw).
  # `gatewayPort` lets the ingress relay reach the guest; `egressPort` lets the
  # guest reach the egress relay bound on the bridge address (without it the
  # backend calls are blackholed and every completion times out).
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

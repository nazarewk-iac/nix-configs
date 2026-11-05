# LiteLLM gateway — a single OpenAI-compatible entrypoint for the local LLM fleet.
#
# Task: docs/tasks/2026-11/litellm-gateway/. This is a HOST-LOCAL module (like
# hosts/brys/llm.nix), not a den aspect, because it is deployed only on etra.
#
# ## State of this work
#
# The container and config are COMPLETE, but the piece that makes it actually
# reach brys is deferred: etra's firewall reaches brys (ping works) yet brys
# drops etra on both 39701 (compat proxy) and 443 (Caddy). Opening that needs a
# firewall change on brys, which is not done here because doing it unattended on
# critical infra is exactly the kind of change that locks you out.
#
# So `autoStart = false`: a `nixos-rebuild switch` on etra will NOT start this
# container. Activation steps (when you want it):
#
#   1. On brys, allow etra -> brys:39701 (the plain-HTTP OpenAI compat proxy).
#   2. Set `autoStart = true` here and rebuild etra.
#   3. Clients talk to `http://<etra>:4000/v1` with the master key.
#
# ## Why no database and no TLS
#
# No Postgres (`DATABASE_URL` unset): that gives no virtual keys, no budgets, no
# spend logs, and one shared master key — which is what we want (research.md).
# No TLS to brys: the egress relay points at brys's plain-HTTP compat proxy, so
# there is no cert/hostname mismatch to solve on the private network.
#
# ## Network shape (the repo's container rule: private network + narrow socat)
#
# The guest has a private veth (no host network). It reaches the outside ONLY
# through two host socat relays bound to the bridge address:
#   - ingress 10.233.100.1:4000  -> guest:4000        (clients -> gateway)
#   - egress  10.233.100.1:8443  -> brys:39701        (gateway -> brys)
# The guest's upstream api_base is therefore http://10.233.100.1:8443/v1.
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
                # Upstream is brys's plain-HTTP compat proxy via the host egress
                # relay; no TLS, so no cert to verify, and that proxy needs no key.
                export BRYS_API_BASE="http://${hostAddress}:${toString egressPort}/v1"
                export BRYS_API_KEY="$(cat /run/secrets/brys-api-key)"
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

  # Egress relay: guest -> brys compat proxy. This is the piece that needs the
  # brys-side firewall opening (see header step 1).
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
}

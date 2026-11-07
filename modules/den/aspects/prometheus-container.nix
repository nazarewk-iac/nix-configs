# A minimal Prometheus, confined in a NixOS container, as a den aspect.
#
# Extracted from brys' inline container (hosts/brys/llm.nix) so more than one host
# can run the same thing: brys scrapes llama-swap + node_exporter, etra scrapes the
# LiteLLM gateway. It is deliberately NOT `kdn.monitoring-prometheus-stack` (that
# also brings Grafana, a secret key and a Caddy vhost — too much for one scrape).
#
# ## What it does
#
# Runs Prometheus in a NixOS container (`privateNetwork = true`) with its TSDB on a
# host directory bind-mounted in (metrics are state, not cache), and scrapes the
# targets a host lists in `kdn.prometheus-container.targets`. The container bridges
# to the host at `hostAddress`/`localAddress`; the host reaches Prometheus for
# queries through the bridge address, so the host side needs a narrow socat relay
# (the host wiring does that, not this aspect — it only names the guest's port).
#
# ## The three rules this tree holds for every aspect
#
# 1. No entity argument. 2. No reachable `enable` option — inclusion is the switch.
# 3. No custom module argument (`config`, `lib`, `pkgs` only).
{ ... }:
{
  kdn.prometheus-container.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.prometheus-container;
    in
    {
      options.kdn.prometheus-container = {
        containerName = lib.mkOption {
          type = lib.types.str;
          default = "prometheus";
        };
        hostAddress = lib.mkOption {
          type = lib.types.str;
          default = "10.233.90.1";
        };
        localAddress = lib.mkOption {
          type = lib.types.str;
          default = "10.233.90.2";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 9090;
        };
        stateDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/prometheus2";
        };
        retentionTime = lib.mkOption {
          type = lib.types.str;
          default = "30d";
        };
        retentionSize = lib.mkOption {
          type = lib.types.str;
          default = "2GB";
        };
        # Each target is a scrape job. `targets` are `host:port` as seen FROM the
        # container (usually the host bridge address + a socat relay port).
        targets = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                job = lib.mkOption { type = lib.types.str; };
                targets = lib.mkOption { type = lib.types.listOf lib.types.str; };
                interval = lib.mkOption {
                  type = lib.types.str;
                  default = "15s";
                };
                metricsPath = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                };
                # A file whose contents are sent as `Authorization: Bearer <contents>`.
                # Must be readable by the prometheus user (the container runs as it).
                authorizationFile = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                };
              };
            }
          );
          default = [ ];
          description = "Scrape jobs run by the containerised Prometheus.";
        };
      };

      config = {
        containers.${cfg.containerName} = {
          autoStart = true;
          restartIfChanged = true;
          privateNetwork = true;
          inherit (cfg) hostAddress localAddress;
          bindMounts.${cfg.stateDir} = {
            hostPath = cfg.stateDir;
            isReadOnly = false;
          };
          config =
            { pkgs, ... }:
            {
              networking.firewall = {
                enable = true;
                allowedTCPPorts = [ cfg.port ];
              };
              services.prometheus = {
                enable = true;
                listenAddress = "0.0.0.0";
                port = cfg.port;
                inherit (cfg) retentionTime;
                extraFlags = [ "--storage.tsdb.retention.size=${cfg.retentionSize}" ];
                scrapeConfigs = map (t: {
                  job_name = t.job;
                  scrape_interval = t.interval;
                  static_configs = [ { targets = t.targets; } ];
                }
                // lib.optionalAttrs (t.metricsPath != null) { metrics_path = t.metricsPath; }
                // lib.optionalAttrs (t.authorizationFile != null) {
                  authorization = {
                    type = "Bearer";
                    credentials_file = t.authorizationFile;
                  };
                }) cfg.targets;
              };
              system.stateVersion = "26.05";
            };
        };
      };
    };
}

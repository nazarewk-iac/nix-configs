# The Prometheus and Grafana stack, as a den aspect. It ports the whole `monitoring` area of the old
# tree.
#
# Old path:
# modules/universal/monitoring/
#
# The old tree keeps every byte. This file is the parallel den implementation.
#
# ## One aspect, one class
#
# The area holds one module, `monitoring/prometheus-stack`. Its whole body sits inside a NixOS guard,
# so `monitoring-prometheus-stack` serves the `nixos` class alone.
#
# ## What the port changes
#
# 1. **`pushgateway.enable` becomes `pushgateway.use`.** `checks/standalone.nix` walks the option tree
#    of every aspect and it stops at an `attrsOf submodule` only. A nested `pushgateway.enable` leaf
#    is therefore reachable, and the check fails on the name. The rename keeps the leaf, the type and
#    the default. `kdn.nix.remote-builder.localhost.use` of the `nix-remote-builder` aspect made the
#    same rename for the same reason, so this follows an in-tree precedent.
# 2. **The top-level `enable` option is gone.** Inclusion is the switch, so the block that the old
#    module puts behind `cfg.enable` now runs whenever a host includes the aspect. Every other option
#    keeps its name and its default.
# 3. **`kdn.env.packages` does not survive.** Design B: the `nixos` target writes
#    `environment.systemPackages`, through ../common/filter-packages.nix.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No reachable `enable` option.** Inclusion is the switch, and the one nested flag is now `use`.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.monitoring-prometheus-stack.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.monitoring.prometheus-stack;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      options.kdn.monitoring.prometheus-stack.caddy.grafana = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "grafana.example.com";
        description = ''
          The host name Caddy serves Grafana under. An empty string adds no Caddy virtual host.
        '';
      };

      options.kdn.monitoring.prometheus-stack.secretKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/grafana/secret-key";
        description = ''
          The file that holds the Grafana secret key. Grafana reads the file at start, through the
          file provider of its own configuration. The operator creates the file.

          nixpkgs 26.05 removed the default secret key, and it asserts that this setting has a
          value. The old module predates that change, so the port adds the option.
        '';
      };

      options.kdn.monitoring.prometheus-stack.pushgateway.use = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run the Prometheus pushgateway next to the server.
        '';
      };

      options.kdn.monitoring.prometheus-stack.retentionSize = lib.mkOption {
        type = lib.types.str;
        default = "5GB";
        description = "The size limit of the time-series database.";
      };

      options.kdn.monitoring.prometheus-stack.retentionTime = lib.mkOption {
        type = lib.types.str;
        default = "90d";
        description = "The time limit of the time-series database.";
      };

      options.kdn.monitoring.prometheus-stack.listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          The address Grafana, Prometheus and the pushgateway bind to.
        '';
      };

      config = lib.mkMerge [
        {
          services.grafana.enable = true;
          services.grafana.settings.server.domain = lib.mkDefault "grafana.localhost";
          services.grafana.settings.server.port = 2342;
          services.grafana.settings.server.addr = cfg.listenAddress;
          services.grafana.settings.security.secret_key = "$__file{${cfg.secretKeyFile}}";
          services.grafana.provision.enable = true;
          services.grafana.provision.datasources.settings.datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              url = "http://${cfg.listenAddress}:9090";
            }
          ];

          # The image renderer needs an older Node, so it stays off.
          services.grafana-image-renderer.enable = false;
          services.grafana-image-renderer.provisionGrafana = true;
          services.grafana-image-renderer.settings.rendering.height = 1000;
          services.grafana-image-renderer.settings.rendering.width = 1900;

          services.prometheus.enable = true;
          services.prometheus.port = 9090;
          services.prometheus.listenAddress = cfg.listenAddress;
          services.prometheus.retentionTime = cfg.retentionTime;
          services.prometheus.extraFlags = [
            "--storage.tsdb.retention.size=${cfg.retentionSize}"
          ];

          environment.systemPackages = filterPackages (
            with pkgs;
            [
              prometheus
              opentsdb
            ]
          );
        }
        (lib.mkIf cfg.pushgateway.use {
          services.prometheus.pushgateway.enable = true;
          services.prometheus.pushgateway.web.listen-address = "${cfg.listenAddress}:9091";
        })
        (lib.mkIf (cfg.caddy.grafana != "") {
          services.grafana.settings.server.domain = cfg.caddy.grafana;
          services.caddy.virtualHosts."${cfg.caddy.grafana}".extraConfig = ''
            reverse_proxy ${cfg.listenAddress}:2342
          '';
        })
      ];
    };
}

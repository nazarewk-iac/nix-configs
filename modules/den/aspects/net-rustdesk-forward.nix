# The `net-rustdesk-forward` aspect. It forwards the RustDesk server ports on a public entrypoint
# to the hub that runs the actual servers, over a mesh link.
#
# ## What it does
#
# One `socat` unit per port: `TCP-LISTEN,<p>,fork` to `TCP:<target>:<p>` for each TCP port, and
# `UDP4-RECVFROM,<p>,fork` to `UDP4-SENDTO:<target>:<p>` for each UDP port. Caddy's HTTP
# `reverse_proxy` cannot carry these protocols, so plain per-port forwarding is the tool.
#
# ## The target
#
# `kdn.net-rustdesk-forward.target` names the host that runs `hbbs` and `hbbr` (the
# `service-rustdesk` aspect). `socat` resolves it when a unit starts, so the target must be
# resolvable from this host — a mesh DNS name is the usual choice. The units restart on failure,
# which also covers a mesh address that changes while the entrypoint runs.
#
# ## The firewall
#
# The aspect opens the forwarded ports on this host's firewall. Traffic from the public interface
# arrives, `socat` relays it, and only the mesh interface carries it onward — no home address is
# ever exposed by DNS or seen by a client.
{ ... }:
{
  kdn.net-rustdesk-forward.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.net-rustdesk-forward;

      mkUnit =
        { proto, port }:
        let
          execStart =
            {
              tcp = "${pkgs.socat}/bin/socat TCP-LISTEN:${builtins.toString port},reuseaddr,fork TCP:${cfg.target}:${builtins.toString port}";
              udp = "${pkgs.socat}/bin/socat -T 300 UDP4-RECVFROM:${builtins.toString port},reuseaddr,fork UDP4-SENDTO:${cfg.target}:${builtins.toString port}";
            }
            .${proto};
        in
        {
          description = "RustDesk ${proto} forward ${builtins.toString port} -> ${cfg.target}";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "netbird-priv.service"
          ];
          wants = [ "network-online.target" ];
          unitConfig.StartLimitIntervalSec = 0;
          serviceConfig = {
            ExecStart = execStart;
            Restart = "always";
            RestartSec = 5;
            DynamicUser = true;
            CapabilityBoundingSet = [ "" ];
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateMounts = true;
            PrivateTmp = true;
            PrivateUsers = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            SystemCallArchitectures = "native";
          };
        };
    in
    {
      options.kdn.net-rustdesk-forward = {
        target = lib.mkOption {
          type = lib.types.str;
          description = ''
            The host that runs `hbbs` and `hbbr`, as a name this host can resolve.
          '';
        };

        tcpPorts = lib.mkOption {
          type = lib.types.listOf lib.types.port;
          default = [
            21115
            21116
            21117
            21118
            21119
          ];
          description = "The TCP ports to forward. The defaults cover `hbbs` and `hbbr`.";
        };

        udpPorts = lib.mkOption {
          type = lib.types.listOf lib.types.port;
          default = [ 21116 ];
          description = "The UDP ports to forward. `hbbs` heartbeats on UDP 21116.";
        };
      };

      config = {
        systemd.services =
          lib.listToAttrs (
            map (p: {
              name = "rustdesk-forward-tcp-${toString p}";
              value = mkUnit {
                proto = "tcp";
                port = p;
              };
            }) cfg.tcpPorts
          )
          // lib.listToAttrs (
            map (p: {
              name = "rustdesk-forward-udp-${toString p}";
              value = mkUnit {
                proto = "udp";
                port = p;
              };
            }) cfg.udpPorts
          );

        networking.firewall.allowedTCPPorts = cfg.tcpPorts;
        networking.firewall.allowedUDPPorts = cfg.udpPorts;
      };
    };
}

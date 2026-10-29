# The build farm: three proxies on `etra`, one per homogeneous system set, and the client entry on
# `oams`.
#
# Why three and not one: yensid's proxy may only serve a homogeneous set — every backend must
# support every advertised system. `briv` serves `aarch64-linux` only, so it cannot share a proxy
# with `anji`, which also serves the darwin systems. One instance per set, each published on its own
# port because they all bind `*:22` inside their container.
#
# Priorities are expressed as `weight` plus `maxConnections`, consumed by the aspect's `priority`
# Lua strategy:
#
#   * `anji` is the fast Apple silicon; it takes aarch64-linux work until it has
#     `maxConnections` in flight, then `briv` (a Pi-class board) picks up the overflow;
#   * `brys` is the only x86_64 builder in the farm, so the strategy is irrelevant there and
#     `leastconn` is enough.
#
# Ports 2201-2203 are chosen to sit beside etra's own sshd on 22. Clients reach them through an SSH
# alias the aspect writes, because `nix.buildMachines` has no port field.
{
  # ---------------------------------------------------------------- etra: the proxies
  etra = {
    # The containers are on a private network, so they need the site resolver by address. knotd
    # listens on `127.0.0.1` and on the drek point-to-point address, not on the LAN address, so the
    # containers use the p2p one: it is a host address, reachable through their veth.
    dnsServers = [ "192.168.40.1" ];
    proxies = {
      # `brys` is the fast x86_64 box. One backend, so no balancing decision.
      x86 = {
        hostPort = 2201;
        hostAddress = "10.233.97.1";
        localAddress = "10.233.97.2";
        systems = [ "x86_64-linux" ];
        strategy = "leastconn";
        builders.brys = {
          address = "brys.lan.etra.net.int.kdn.im";
          # The Ryzen 9 5950X host: 12 of its 16 cores are free when no model is resident.
          maxConnections = 12;
        };
      };

      # Both Apple systems, one backend, so this proxy is a stable name for `anji`, not a balancer.
      darwin = {
        hostPort = 2202;
        hostAddress = "10.233.97.5";
        localAddress = "10.233.97.6";
        systems = [
          "aarch64-darwin"
          "x86_64-darwin"
        ];
        strategy = "leastconn";
        builders.anji = {
          address = "anji.lan.etra.net.int.kdn.im";
          maxConnections = 4;
        };
      };

      # The interesting one: `anji` first, `briv` as the slow overflow.
      arm = {
        hostPort = 2203;
        hostAddress = "10.233.97.9";
        localAddress = "10.233.97.10";
        systems = [ "aarch64-linux" ];
        # The `priority` Lua fetch is not working yet: HAProxy's `core.get_server_conns` is not
        # available in this build's Lua context, so the fetch throws and the proxy refuses every
        # connection. `leastconn` still balances correctly, it just cannot honour "anji first".
        # Left as a follow-up in the task; see the worklog entry.
        strategy = "leastconn";
        builders.anji = {
          address = "anji.lan.etra.net.int.kdn.im";
          weight = 100;
          # Four performance/efficiency cores, and each build is a QEMU guest.
          maxConnections = 4;
        };
        builders.briv = {
          address = "briv.lan.etra.net.int.kdn.im";
          # Low priority: a Pi-class board. Only used when `anji` is saturated.
          weight = 1;
        };
      };
    };
  };

  # ---------------------------------------------------------------- oams: the client
  # One entry per system set, pointing at the proxy ports. The address is a local name for etra, so
  # nothing outside the LAN can resolve it.
  oams = {
    clients = {
      x86 = {
        address = "buildfarm-x86.lan.etra.net.int.kdn.im";
        hostPort = 2201;
        systems = [ "x86_64-linux" ];
        user = "kdn-nix-remote-build";
        identityFile = "/run/configs/nix/ssh/kdn-nix-remote-build/id_ed25519";
        speedFactor = 32;
        maxJobs = 8;
      };
      darwin = {
        address = "buildfarm-darwin.lan.etra.net.int.kdn.im";
        hostPort = 2202;
        systems = [
          "aarch64-darwin"
          "x86_64-darwin"
        ];
        user = "kdn-nix-remote-build";
        identityFile = "/run/configs/nix/ssh/kdn-nix-remote-build/id_ed25519";
        speedFactor = 8;
        maxJobs = 4;
      };
      arm = {
        address = "buildfarm-arm.lan.etra.net.int.kdn.im";
        hostPort = 2203;
        systems = [ "aarch64-linux" ];
        user = "kdn-nix-remote-build";
        identityFile = "/run/configs/nix/ssh/kdn-nix-remote-build/id_ed25519";
        speedFactor = 8;
        maxJobs = 4;
      };
    };
    # The three local names above all resolve to etra on the LAN. Kept here rather than in a DNS
    # zone so the PoC needs no DNS change; a zone entry would be the production form.
    hosts = {
      "buildfarm-x86.lan.etra.net.int.kdn.im" = "192.168.73.1";
      "buildfarm-darwin.lan.etra.net.int.kdn.im" = "192.168.73.1";
      "buildfarm-arm.lan.etra.net.int.kdn.im" = "192.168.73.1";
    };
  };
}

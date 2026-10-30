# The build farm: one proxy container on `etra`, one client entry per system set.
#
# The fleet is heterogeneous (brys is x86-only; etra/brys run LLM inference), and HAProxy's
# `balance` is per TCP connection with no idea which system Nix asked for. So each **system set gets
# its own listener port** with a homogeneous pool; a client picks the pool by dialling that port.
# `maxConnections` is the only thing that ever makes `first` spill to the next pool member.
#
#   x86    : brys        — the fast box, capped low enough that a build cannot starve a resident model
#   arm    : anji, briv  — anji is fast Apple silicon; briv is a Pi-class fallback only reached at cap
#   darwin : anji        — the only darwin-capable builder
{
  etra = {
    proxy = {
      hostAddress = "10.233.98.1";
      localAddress = "10.233.98.2";
      # Answer only on the LAN: the SSH forwarder must not face the WAN or the NetBird mesh, which
      # is also what makes "away ⇒ build local" true rather than merely configured.
      bindAddress = "192.168.73.1";
      lanInterface = "lan";
      # The proxy must resolve builder names; a private-network container has no upstream of its own.
      dnsServers = [ "192.168.40.1" ];
      builders = {
        brys = {
          address = "brys.lan.etra.net.int.kdn.im";
          # 12 of the box's 16 physical cores; a model can have the rest.
          maxConnections = 12;
        };
        anji = {
          address = "anji.lan.etra.net.int.kdn.im";
          # Four performance/efficiency cores total. `anji` is in TWO pools (arm and darwin), and
          # HAProxy caps per backend server, so keep each pool's share small: 2+2 = 4 in the worst
          # case, as many concurrent builds as the box can carry.
          maxConnections = 2;
        };
        briv = {
          address = "briv.lan.etra.net.int.kdn.im";
        };
      };
      pools = {
        x86 = {
          port = 2222;
          systems = [ "x86_64-linux" ];
          builderOrder = [ "brys" ];
        };
        arm = {
          port = 2223;
          systems = [ "aarch64-linux" ];
          builderOrder = [
            "anji"
            "briv"
          ];
        };
        darwin = {
          port = 2224;
          systems = [
            "aarch64-darwin"
            "x86_64-darwin"
          ];
          builderOrder = [ "anji" ];
        };
      };
    };
  };

  oams = {
    # The laptop thermal-throttles (8 physical cores, 16 threads). The remote farm is the fast
    # path; when it is unreachable this local fallback should use the physical cores, not every
    # hyperthread, so a long local build does not cook the chassis.
    localMaxJobs = 8;
    # `auto` (the default switch mode) keeps brys on while one of these SSIDs is in range — the
    # places with a fast LAN path to it — and off otherwise. On/off are manual overrides.
    autoWifi = [
      "Covfefe"
      "dropout-wafer"
    ];
    # One SSH alias per system set: `buildMachines` has no port field, so the port is in the alias.
    clients = {
      x86 = {
        alias = "buildfarm-x86";
        address = "192.168.73.1";
        hostPort = 2222;
        systems = [ "x86_64-linux" ];
        user = "kdn-nix-remote-build";
        identityFile = "/run/configs/nix/ssh/kdn-nix-remote-build/id_ed25519";
        maxJobs = 8;
        speedFactor = 32;
        # This pool is brys alone, so `build-farm-brys off` drops it and x86 builds go local.
        toggleable = true;
      };
      arm = {
        alias = "buildfarm-arm";
        address = "192.168.73.1";
        hostPort = 2223;
        systems = [ "aarch64-linux" ];
        user = "kdn-nix-remote-build";
        identityFile = "/run/configs/nix/ssh/kdn-nix-remote-build/id_ed25519";
        maxJobs = 4;
        speedFactor = 8;
      };
      darwin = {
        alias = "buildfarm-darwin";
        address = "192.168.73.1";
        hostPort = 2224;
        systems = [
          "aarch64-darwin"
          "x86_64-darwin"
        ];
        user = "kdn-nix-remote-build";
        identityFile = "/run/configs/nix/ssh/kdn-nix-remote-build/id_ed25519";
        maxJobs = 4;
        speedFactor = 8;
      };
    };
  };
}

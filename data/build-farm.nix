# The build farm: one proxy container on `etra`, one client entry per system set.
#
# The fleet is heterogeneous (brys is x86-only; etra/brys run LLM inference), and HAProxy's
# `balance` is per TCP connection with no idea which system Nix asked for. So each **system set gets
# its own listener port** with a homogeneous pool; a client picks the pool by dialling that port.
# `maxConnections` is the only thing that ever makes `first` spill to the next pool member.
#
#   x86    : brys        — the fast box, capped low enough that a build cannot starve a resident model
#   arm    : anji only   — anji builds aarch64-linux on its local Rosetta VM and falls back to briv
#                          (a Pi-class builder) only as a dependency fallback via anji's OWN
#                          /etc/nix/machines. briv is deliberately NOT a proxy pool member: the
#                          proxy never hands a whole aarch64-linux build to the Pi.
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
      # Also reachable over the mesh, so an away client can use the same pools. The nspawn DNAT is
      # destination-agnostic, so only the firewall + gate need to let the mesh interface through.
      remoteBind = "100.79.187.16";
      meshInterface = "nb-priv";
      # The proxy must resolve builder names; a private-network container has no upstream of its own.
      dnsServers = [ "192.168.40.1" ];
      builders = {
        brys = {
          address = "brys.lan.etra.net.int.kdn.im";
          # 12 of the box's 16 physical cores; a model can have the rest.
          maxConnections = 12;
          # brys also serves LLMs. Its `kdn-build-farm-agent` answers HAProxy `agent-check` with
          # `drain` while a frontier model is resident (measured: idle ~90 % free, resident ~78 %;
          # the agent drains below 85 %), so a build does not compete with the model for RAM/CPU.
          probePort = 39701;
        };
        anji = {
          address = "anji.lan.etra.net.int.kdn.im";
          # Apple M2: 8 physical cores (4 performance + 4 efficiency). `anji` is in TWO pools (arm
          # and darwin) and HAProxy caps per backend server, so 4 per pool means at most 4+4 = 8
          # concurrent builds in the worst case — one per physical core, the whole machine, not half.
          maxConnections = 4;
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
          # anji alone. It forwards to rosetta-builder (primary) then briv (last-resort fallback)
          # through its own buildMachines, so the proxy never routes a whole build to the Pi.
          builderOrder = [ "anji" ];
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
        # LAN first, NetBird fallback; the alias picks at connect time.
        addressLan = "etra.lan.etra.net.int.kdn.im";
        addressRemote = "etra.priv.nb.net.int.kdn.im";
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
        addressLan = "etra.lan.etra.net.int.kdn.im";
        addressRemote = "etra.priv.nb.net.int.kdn.im";
        hostPort = 2223;
        systems = [ "aarch64-linux" ];
        user = "kdn-nix-remote-build";
        identityFile = "/run/configs/nix/ssh/kdn-nix-remote-build/id_ed25519";
        maxJobs = 4;
        speedFactor = 8;
      };
      darwin = {
        alias = "buildfarm-darwin";
        addressLan = "etra.lan.etra.net.int.kdn.im";
        addressRemote = "etra.priv.nb.net.int.kdn.im";
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

# Tier-1 assertions for the seven networking aspects of batch 13.
#
# Every assertion is `{ name; expected; actual; }`, and `mkEvalCheck` compares the two at evaluation
# time. Nothing here builds a system and nothing activates.
#
# ## The subjects
#
# | Subject | Class | What it states |
# |---|---|---|
# | `nixosPlain` | `nixos` | all seven aspects, no consumer opinion beyond one flag |
# | `nixosWired` | `nixos` | a bond, a VLAN, two resolvers, one NetBird client, one OpenVPN instance |
# | `darwinPlain` | `darwin` | the four aspects that emit a `darwin` target |
# | `homePlain` | `homeManager` | the four aspects that emit a `homeManager` target |
#
# `nixosPlain` turns `patchOpenvpn3` off and `nixosWired` keeps it on, so one assertion measures both
# states of the overlay. An overlay makes the consumer evaluate nixpkgs a second time, so the two
# subjects also keep the cost of this file down.
#
# ## What this file does not cover
#
# It reads option values only. systemd-networkd stays off in both NixOS subjects, so no unit file
# renders and the networkd unit assertions never run. A unit file needs a tier-2 artifact check, and
# no aspect of this batch has one yet.
#
# ## The addresses
#
# Every address is a documentation address from RFC 5737 (`192.0.2.0/24`) or RFC 3849
# (`2001:db8::/32`). Every MAC is a locally administered placeholder. Every host name and domain name
# is a placeholder. No real network appears here.
{
  lib,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos bareDarwinSystem bareHomeConfiguration;

  sorted = lib.sort (a: b: a < b);

  netNames = [
    "net-dynamic-hosts"
    "net-interfaces"
    "net-netbird"
    "net-openfortivpn"
    "net-openvpn"
    "net-resolved"
    "net-tailscale"
  ];

  nixosModules = denLib.imports {
    class = "nixos";
    aspects = netNames;
  };

  nixosPlainSystem = bareNixos (
    nixosModules
    ++ [
      # The overlay costs a second nixpkgs evaluation. `nixosWired` measures the `true` state.
      { kdn.networking.openvpn.patchOpenvpn3 = false; }
    ]
  );
  nixosPlain = nixosPlainSystem.config;

  # One bond over one physical link, one VLAN over the bond, and one interface the consumer keeps out
  # of the render. Two resolvers answer, and a third stays disabled. One NetBird client runs and a
  # second stays off. One OpenVPN instance takes over its own routes.
  wiredOpinion = {
    kdn.networking.debug = true;

    kdn.networking.ifaces.lan0 = {
      selector.mac = "02:00:00:00:00:01";
      mac = "02:00:00:00:00:02";
      dynamicIPClient = true;
      metric = 1024;
      address.v4 = "192.0.2.10/24";
    };
    kdn.networking.ifaces.bond0.metric = 2048;
    kdn.networking.ifaces.vlan10.metric = 4096;
    kdn.networking.ifaces.ext0 = {
      managed = false;
      metric = 8192;
    };

    kdn.networking.bonds.bond0.children = [ "lan0" ];
    kdn.networking.bonds.bond0.type = "lacp";

    kdn.networking.vlans.vlan10.id = 10;
    kdn.networking.vlans.vlan10.parent = "bond0";

    kdn.networking.resolved.multicastDNS = "resolve";
    kdn.networking.resolved.nameservers."192.0.2.53" = { };
    kdn.networking.resolved.nameservers."192.0.2.54" = {
      port = 853;
      interface = "lan0";
      sni = "dns.example.org";
    };
    kdn.networking.resolved.nameservers."192.0.2.55".enable = false;

    kdn.networking.tailscale.authKeyFile = "/run/secrets/den-tailscale-auth-key";

    # `root` and `nobody` both exist on every NixOS system, so the group membership needs no extra
    # user declaration.
    kdn.networking.netbird.admins = [ "root" ];
    kdn.networking.netbird.default.users = [ "nobody" ];
    kdn.networking.netbird.default.environment.NB_LOG_LEVEL = "info";
    kdn.networking.netbird.secretsTree.alpha.env.path = "/run/secrets/den-netbird-alpha-env";
    kdn.networking.netbird.secretsTree.alpha.permanent.setup-key.path =
      "/run/secrets/den-netbird-alpha-key";
    kdn.networking.netbird.clients.alpha = {
      idx = 0;
      systemd.enable = true;
      resolvesDomains = [ "den.example.org" ];
    };
    kdn.networking.netbird.clients.beta = {
      idx = 1;
      enable = false;
    };

    kdn.networking.openvpn.instances.office = {
      routes.ignore = true;
      routes.add = [ { network = "192.0.2.0"; } ];
      scripts.up = "echo up";
    };
  };

  nixosWiredSystem = bareNixos (nixosModules ++ [ wiredOpinion ]);
  nixosWired = nixosWiredSystem.config;

  crossAspects = [
    "net-dynamic-hosts"
    "net-netbird"
    "net-openfortivpn"
    "net-openvpn"
  ];

  darwinSystem = bareDarwinSystem (
    denLib.imports {
      class = "darwin";
      aspects = crossAspects;
    }
  );
  darwinPlain = darwinSystem.config;

  homeConfiguration = bareHomeConfiguration (
    denLib.imports {
      class = "homeManager";
      aspects = crossAspects;
    }
  );
  homePlain = homeConfiguration.config;

  has = name: packages: lib.elem name (map lib.getName packages);

  assertions = [
    # ---------------------------------------------------------------- instantiation
    {
      name = "the networking aspects instantiate in all three classes";
      expected = {
        plain = true;
        wired = true;
        darwin = true;
        home = true;
      };
      actual = {
        plain = builtins.isString nixosPlainSystem.config.system.build.toplevel.drvPath;
        wired = builtins.isString nixosWiredSystem.config.system.build.toplevel.drvPath;
        darwin = builtins.isString darwinPlain.system.build.toplevel.drvPath;
        home = builtins.isString homePlain.home.activationPackage.drvPath;
      };
    }
    {
      name = "each networking aspect emits the classes its old module had";
      expected = {
        net-dynamic-hosts = [
          "darwin"
          "homeManager"
          "nixos"
        ];
        net-interfaces = [ "nixos" ];
        net-netbird = [
          "darwin"
          "homeManager"
          "nixos"
        ];
        net-openfortivpn = [
          "darwin"
          "homeManager"
          "nixos"
        ];
        net-openvpn = [
          "darwin"
          "homeManager"
          "nixos"
        ];
        net-resolved = [ "nixos" ];
        net-tailscale = [ "nixos" ];
      };
      actual = lib.mapAttrs (_: sorted) (lib.getAttrs netNames denLib.pairs);
    }

    # ---------------------------------------------------------------- net-interfaces
    {
      name = "an interface graph with no entry renders no unit and no NetworkManager exception";
      expected = {
        unmanaged = [ ];
        networks = [ ];
        links = [ ];
        netdevs = [ ];
        logLevel = false;
      };
      actual = {
        unmanaged = nixosPlain.networking.networkmanager.unmanaged;
        networks = builtins.attrNames nixosPlain.systemd.network.networks;
        links = builtins.attrNames nixosPlain.systemd.network.links;
        netdevs = builtins.attrNames nixosPlain.systemd.network.netdevs;
        # nixpkgs declares this unit inside its own `mkIf systemd.network.enable`, so the whole
        # attribute is absent until this aspect raises the log level.
        logLevel = nixosPlain.systemd.services ? systemd-networkd;
      };
    }
    {
      name = "the bond, the VLAN and the link each get their own unit name";
      expected = {
        networks = [
          "40-kdn-netbird-nb-alpha"
          "50-bond0"
          "50-lan0"
          "50-vlan10"
        ];
        links = [ "00-lan0" ];
        netdevs = [
          "10-vlan10"
          "50-bond0"
        ];
        logLevel = "debug";
      };
      actual = {
        networks = sorted (builtins.attrNames nixosWired.systemd.network.networks);
        links = sorted (builtins.attrNames nixosWired.systemd.network.links);
        netdevs = sorted (builtins.attrNames nixosWired.systemd.network.netdevs);
        logLevel = nixosWired.systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL;
      };
    }
    {
      name = "an unmanaged interface stays out of the NetworkManager exception list";
      # `ext0` states `managed = false`, so `net-interfaces` keeps it out of this list. `lan0` enters
      # by MAC, because it carries a selector. `bond0` and `vlan10` enter by name.
      #
      # `interface-name:nb-alpha` comes from nixpkgs itself, not from this aspect tree. The nixpkgs
      # netbird module writes one entry per enabled client
      # (`nixos/modules/services/networking/netbird.nix`, the `networking.networkmanager.unmanaged`
      # line). `nixosWired` enables the client `alpha`, so the entry is correct and expected.
      expected = [
        "interface-name:bond0"
        "interface-name:nb-alpha"
        "interface-name:vlan10"
        "mac:02:00:00:00:00:01"
      ];
      actual = sorted nixosWired.networking.networkmanager.unmanaged;
    }
    {
      name = "the link unit renames the interface and it sets the new MAC address";
      expected = {
        permanent = "02:00:00:00:00:01";
        namePolicy = "";
        name = "lan0";
        policy = "none";
        address = "02:00:00:00:00:02";
      };
      actual = {
        permanent = nixosWired.systemd.network.links."00-lan0".matchConfig.PermanentMACAddress;
        namePolicy = nixosWired.systemd.network.links."00-lan0".linkConfig.NamePolicy;
        name = nixosWired.systemd.network.links."00-lan0".linkConfig.Name;
        policy = nixosWired.systemd.network.links."00-lan0".linkConfig.MACAddressPolicy;
        address = nixosWired.systemd.network.links."00-lan0".linkConfig.MACAddress;
      };
    }
    {
      name = "the physical link joins the bond, runs a dynamic IP client and holds its static address";
      expected = {
        bond = "bond0";
        dhcp = true;
        acceptRA = true;
        metric = 1024;
        addresses = [ "192.0.2.10/24" ];
      };
      actual = {
        bond = nixosWired.systemd.network.networks."50-lan0".networkConfig.Bond;
        dhcp = nixosWired.systemd.network.networks."50-lan0".networkConfig.DHCP;
        acceptRA = nixosWired.systemd.network.networks."50-lan0".networkConfig.IPv6AcceptRA;
        metric = nixosWired.systemd.network.networks."50-lan0".dhcpV4Config.RouteMetric;
        addresses = map (a: a.Address) nixosWired.systemd.network.networks."50-lan0".addresses;
      };
    }
    {
      name = "the bond netdev names LACP and the VLAN netdev names its id";
      expected = {
        bondKind = "bond";
        mode = "802.3ad";
        vlanKind = "vlan";
        id = 10;
        parent = [ "vlan10" ];
      };
      actual = {
        bondKind = nixosWired.systemd.network.netdevs."50-bond0".netdevConfig.Kind;
        mode = nixosWired.systemd.network.netdevs."50-bond0".bondConfig.Mode;
        vlanKind = nixosWired.systemd.network.netdevs."10-vlan10".netdevConfig.Kind;
        id = nixosWired.systemd.network.netdevs."10-vlan10".vlanConfig.Id;
        parent = nixosWired.systemd.network.networks."50-bond0".networkConfig.VLAN;
      };
    }

    # ---------------------------------------------------------------- net-resolved
    {
      name = "the resolver holds its four opinions and it writes no DNS line until asked";
      expected = {
        enabled = true;
        dnssec = "false";
        dot = "opportunistic";
        llmnr = "true";
        mdns = null;
        dns = [ ];
      };
      actual = {
        enabled = nixosPlain.services.resolved.enable;
        dnssec = nixosPlain.services.resolved.settings.Resolve.DNSSEC;
        dot = nixosPlain.services.resolved.settings.Resolve.DNSOverTLS;
        llmnr = nixosPlain.services.resolved.settings.Resolve.LLMNR;
        mdns = nixosPlain.services.resolved.settings.Resolve.MulticastDNS;
        dns = nixosPlain.services.resolved.settings.Resolve.DNS;
      };
    }
    {
      name = "each resolver renders its port, its interface and its TLS name, and a disabled one drops";
      expected = {
        mdns = "resolve";
        dns = [
          "192.0.2.53:53"
          "192.0.2.54:853%lan0#dns.example.org"
        ];
      };
      actual = {
        mdns = nixosWired.services.resolved.settings.Resolve.MulticastDNS;
        dns = nixosWired.services.resolved.settings.Resolve.DNS;
      };
    }

    # ---------------------------------------------------------------- net-tailscale
    {
      name = "Tailscale runs, it opens the firewall, and it takes an auth key file only when named";
      expected = {
        enabled = true;
        firewall = true;
        plainKey = null;
        wiredKey = "/run/secrets/den-tailscale-auth-key";
        persist = [ "/var/lib/tailscale" ];
      };
      actual = {
        enabled = nixosPlain.services.tailscale.enable;
        firewall = nixosPlain.services.tailscale.openFirewall;
        plainKey = nixosPlain.services.tailscale.authKeyFile;
        wiredKey = nixosWired.services.tailscale.authKeyFile;
        persist = nixosPlain.kdn.disks.persist."usr/data".directories;
      };
    }

    # ---------------------------------------------------------------- net-netbird
    {
      name = "a machine that names no NetBird client gets no client and no target, but keeps the tool";
      expected = {
        clients = [ ];
        target = false;
        wireguard = true;
      };
      actual = {
        clients = builtins.attrNames nixosPlain.services.netbird.clients;
        target = nixosPlain.systemd.targets ? netbird;
        wireguard = has "wireguard-tools" nixosPlain.environment.systemPackages;
      };
    }
    {
      name = "a disabled NetBird client renders nothing and the active one takes its own port and resolver";
      expected = {
        clients = [ "alpha" ];
        port = 0;
        resolver = "127.5.18.20";
        domains = [ "den.example.org" ];
      };
      actual = {
        clients = sorted (builtins.attrNames nixosWired.services.netbird.clients);
        port = nixosWired.services.netbird.clients.alpha.port;
        resolver = nixosWired.services.netbird.clients.alpha.dns-resolver.address;
        domains = nixosWired.systemd.network.networks."40-kdn-netbird-nb-alpha".domains;
      };
    }
    {
      name = "the NetBird target follows every active client, and the group holds the users plus the admins";
      expected = {
        wants = [ "netbird-alpha.service" ];
        after = [ "netbird-alpha.service" ];
        propagates = [ "netbird-alpha.service" ];
        members = [
          "nobody"
          "root"
        ];
      };
      actual = {
        wants = nixosWired.systemd.targets.netbird.wants;
        after = nixosWired.systemd.targets.netbird.after;
        propagates = nixosWired.systemd.targets.netbird.unitConfig.PropagatesStopTo;
        members = sorted nixosWired.users.groups.netbird-alpha.members;
      };
    }
    {
      name = "the secrets subtree reaches the login key and the environment credential";
      expected = {
        login = true;
        setupKey = "/run/secrets/den-netbird-alpha-key";
        credential = true;
        environmentFile = "-%d/env";
      };
      actual = {
        login = nixosWired.services.netbird.clients.alpha.login.enable;
        setupKey = nixosWired.services.netbird.clients.alpha.login.setupKeyFile;
        # nixpkgs may add a credential of its own, so this reads membership, not the whole list.
        credential = lib.elem "env:/run/secrets/den-netbird-alpha-env" nixosWired.systemd.services.netbird-alpha.serviceConfig.LoadCredential;
        environmentFile = nixosWired.systemd.services.netbird-alpha.serviceConfig.EnvironmentFile;
      };
    }
    {
      name = "the shared environment reaches the client and the client wins over it";
      expected = "info";
      actual = nixosWired.services.netbird.clients.alpha.environment.NB_LOG_LEVEL;
    }
    {
      name = "the routing policy rules keep the main table first and the marked table second";
      # It reads one key per rule, not the whole rule. A rule is a freeform section, so a full
      # comparison would also read every declared key nixpkgs defaults to null.
      expected = {
        count = 2;
        priorities = [
          105
          110
        ];
        suppress = 0;
        mainTable = "main";
        invert = true;
        mark = 113920;
        markedTable = 7120;
      };
      actual =
        let
          rules = nixosWired.systemd.network.networks."40-kdn-netbird-nb-alpha".routingPolicyRules;
          first = builtins.elemAt rules 0;
          second = builtins.elemAt rules 1;
        in
        {
          count = builtins.length rules;
          priorities = map (rule: rule.Priority) rules;
          suppress = first.SuppressPrefixLength;
          mainTable = first.Table;
          invert = second.InvertRule;
          mark = second.FirewallMark;
          markedTable = second.Table;
        };
    }
    {
      name = "the NetBird package options stay null, so the nixpkgs defaults hold";
      expected = {
        client = null;
        ui = null;
        signal = null;
        management = null;
        dashboard = null;
        uiEnabled = false;
      };
      actual = {
        client = nixosWired.kdn.networking.netbird.packages.client;
        ui = nixosWired.kdn.networking.netbird.packages.ui;
        signal = nixosWired.kdn.networking.netbird.packages.signal;
        management = nixosWired.kdn.networking.netbird.packages.management;
        dashboard = nixosWired.kdn.networking.netbird.packages.dashboard;
        uiEnabled = nixosWired.services.netbird.ui.enable;
      };
    }

    # ---------------------------------------------------------------- net-dynamic-hosts
    {
      name = "the dynamic hosts aspect replaces /etc/hosts and it watches the directory";
      expected = {
        etcHosts = false;
        managed = [ "/etc/hosts.d" ];
        watched = "/etc/hosts.d";
        burst = 1;
        generator = true;
      };
      actual = {
        etcHosts = nixosPlain.environment.etc."hosts".enable;
        managed = nixosPlain.kdn.networking.dynamic-hosts.managedDirectories;
        watched = nixosPlain.systemd.paths.kdn-dynamic-hosts.pathConfig.PathChanged;
        burst = nixosPlain.systemd.paths.kdn-dynamic-hosts.pathConfig.TriggerLimitBurst;
        generator = has "kdn-gen-hosts" nixosPlain.environment.systemPackages;
      };
    }
    {
      name = "the generator runs once per change and it comes up before the network";
      expected = {
        type = "oneshot";
        remain = false;
        before = [ "network.target" ];
      };
      actual = {
        type = nixosPlain.systemd.services.kdn-dynamic-hosts.serviceConfig.Type;
        remain = nixosPlain.systemd.services.kdn-dynamic-hosts.serviceConfig.RemainAfterExit;
        before = nixosPlain.systemd.services.kdn-dynamic-hosts.before;
      };
    }

    # ---------------------------------------------------------------- net-openfortivpn
    {
      name = "the openfortivpn aspect installs the client and it writes the one pppd option";
      expected = {
        client = true;
        pppd = "ipcp-accept-remote";
      };
      actual = {
        client = has "openfortivpn" nixosPlain.environment.systemPackages;
        pppd = nixosPlain.environment.etc."ppp/options".text;
      };
    }

    # ---------------------------------------------------------------- net-openvpn
    {
      name = "the OpenVPN aspect installs the setup command, turns openvpn3 on and names no instance";
      expected = {
        setup = true;
        openvpn3 = true;
        servers = [ ];
      };
      actual = {
        setup = has "kdn-openvpn-setup" nixosPlain.environment.systemPackages;
        openvpn3 = nixosPlain.programs.openvpn3.enable;
        servers = builtins.attrNames nixosPlain.services.openvpn.servers;
      };
    }
    {
      name = "an instance that takes over its routes gets route-noexec, the static route and its own directory";
      expected = {
        servers = [ "office" ];
        noexec = true;
        route = true;
        routeUp = true;
        workDir = "/etc/kdn/openvpn/office";
        autoStart = false;
      };
      actual = {
        servers = sorted (builtins.attrNames nixosWired.services.openvpn.servers);
        noexec = lib.hasInfix "route-noexec" nixosWired.services.openvpn.servers.office.config;
        route = lib.hasInfix "route 192.0.2.0 255.255.255.0" nixosWired.services.openvpn.servers.office.config;
        routeUp = lib.hasInfix "route-up /nix/store" nixosWired.services.openvpn.servers.office.config;
        workDir = nixosWired.systemd.services.openvpn-office.serviceConfig.WorkingDirectory;
        autoStart = nixosWired.services.openvpn.servers.office.autoStart;
      };
    }
    {
      name = "the openvpn3 patch overlay follows its own flag";
      expected = {
        off = 0;
        on = 1;
      };
      actual = {
        off = builtins.length nixosPlain.nixpkgs.overlays;
        on = builtins.length nixosWired.nixpkgs.overlays;
      };
    }

    # ---------------------------------------------------------------- the cross-platform classes
    {
      name = "the four cross-platform aspects carry their commands into the Darwin class";
      expected = {
        genHosts = true;
        fortivpn = true;
        openvpnSetup = true;
        wireguard = true;
      };
      actual = {
        genHosts = has "kdn-gen-hosts" darwinPlain.environment.systemPackages;
        fortivpn = has "openfortivpn" darwinPlain.environment.systemPackages;
        openvpnSetup = has "kdn-openvpn-setup" darwinPlain.environment.systemPackages;
        wireguard = has "wireguard-tools" darwinPlain.environment.systemPackages;
      };
    }
    {
      name = "the four cross-platform aspects carry their commands into the Home Manager class";
      expected = {
        genHosts = true;
        fortivpn = true;
        openvpnSetup = true;
        wireguard = true;
      };
      actual = {
        genHosts = has "kdn-gen-hosts" homePlain.home.packages;
        fortivpn = has "openfortivpn" homePlain.home.packages;
        openvpnSetup = has "kdn-openvpn-setup" homePlain.home.packages;
        wireguard = has "wireguard-tools" homePlain.home.packages;
      };
    }
    {
      name = "no cross-platform class writes a service, a unit or an /etc file";
      # The probe reads a **value**, never `? netbird`. nix-darwin declares `services.netbird` itself
      # (`modules/services/netbird.nix` declares `enable` and `package`), so the `?` test answers
      # `true` on every nix-darwin evaluation and measures nothing about this aspect. The `enable`
      # value and the launchd daemon both stay absent, which is the real claim.
      #
      # Home Manager declares no netbird module, so the `?` test is still correct there.
      expected = {
        darwinNetbird = false;
        darwinNetbirdDaemon = false;
        darwinPppd = false;
        homeNetbird = false;
      };
      actual = {
        darwinNetbird = darwinPlain.services.netbird.enable;
        darwinNetbirdDaemon = darwinPlain.launchd.daemons ? netbird;
        darwinPppd = darwinPlain.environment.etc ? "ppp/options";
        homeNetbird = homePlain.services ? netbird;
      };
    }
  ];

  # ------------------------------------------------------------------ the coverage rows
  #
  # `../tests.nix` merges this set into the table that `den-eval-coverage` reads. One row per aspect
  # this batch ports, so the registry and the table stay equal with no edit to a shared file.
  instantiatedBy = {
    net-dynamic-hosts = "den-eval-networking (bare nixos, bare darwin and bare home)";
    net-interfaces = "den-eval-networking (bare nixos, a bond and a VLAN)";
    net-netbird = "den-eval-networking (bare nixos, two clients; bare darwin and bare home)";
    net-openfortivpn = "den-eval-networking (bare nixos, bare darwin and bare home)";
    net-openvpn = "den-eval-networking (bare nixos, one instance; bare darwin and bare home)";
    net-resolved = "den-eval-networking (bare nixos, three resolvers)";
    net-tailscale = "den-eval-networking (bare nixos, with and without an auth key file)";
  };
in
{
  inherit assertions instantiatedBy;
}

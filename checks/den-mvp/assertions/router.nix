# The `net-router` aspect family, over five bare NixOS consumers.
#
# | Subject | It holds |
# |---|---|
# | `base` | `net-router` alone, no consumer data |
# | `dhcpOnly` | `net-router-dhcp`, no consumer data |
# | `ddns` | `net-router-ddns`, no net graph |
# | `full` | `net-router-ddns` and `net-router-dns-rewrites`, with a two-net graph |
# | `debugOn` | the `full` graph plus `debug.all` |
#
# ## What this file proves
#
# 1. **The family seam is real.** Each aspect starts its own daemons and writes its own templates.
#    `base` alone starts no Kea, no knot and no kresd.
# 2. **The `sops.templates` port works.** The aspects write `kdn.networking.router.templates`, and
#    every subject below carries **no** `sops-nix` module. `checks/den-mvp/assertions/hw.nix:488-497`
#    asserts the shared harness stays sops-free, and this file keeps it that way.
# 3. **The Kea renderer needs no import-from-derivation.** One assertion parses the rendered content
#    with `builtins.fromJSON`, so the content is a plain string and no derivation is built.
# 4. **No host name survives the port.** The old module writes one literal DDNS key id three times.
#    One assertion looks for that host name and expects to find none.
#
# ## Every value here is a placeholder
#
# No host name, no address, no CIDR, no MAC address and no zone of any real machine appears below.
# Each value comes from a documentation range: RFC 5737 for IPv4, RFC 3849 for IPv6, RFC 7042 for a
# MAC address and RFC 2606 for a DNS name.
{
  lib,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos;

  modulesFor = class: aspects: denLib.imports { inherit class aspects; };

  sorted = builtins.sort (a: b: a < b);

  # The host name, plus a short drop-in infix so every rendered path below is short. Every subject
  # carries this set.
  consumer = {
    networking.hostName = "router";
    kdn.networking.router.dropin.infix = "test";
  };

  # `addr.public.*` belongs to `net-router-ddns` alone, and it has no default on purpose: a router
  # that publishes its own address must name both files. So only a DDNS subject writes it. A subject
  # that writes it without the aspect fails with "the option does not exist", and that failure is
  # the proof the family seam holds.
  ddnsAddr = {
    kdn.networking.router.addr.public.ipv4.path = "/dev/null";
    kdn.networking.router.addr.public.ipv6.path = "/dev/null";
  };

  # One uplink and one trusted LAN. The LAN holds one static lease for the router itself, because
  # every `addressing` entry gives the router its own address from the entry named after the host.
  graph = {
    kdn.networking.router = {
      dhcp-ddns.suffix = "example.";

      nets.wan = {
        type = "wan";
        interfaces = [ "eth0" ];
        wan.asDefaultDNS = true;
        wan.gateway = [ "192.0.2.1" ];
        address = [ "192.0.2.2/30" ];
      };

      nets.lan = {
        type = "lan";
        interfaces = [ "eth1" ];
        lan.uplink = "wan";
        firewall.trusted = true;

        addressing.v4 = {
          subnet-id = 1;
          network = "198.51.100.0";
          netmask = "24";
          pools.dynamic = {
            start = "198.51.100.100";
            end = "198.51.100.200";
          };
          hosts.router.ip = "198.51.100.1";
          hosts.workstation = {
            ip = "198.51.100.10";
            ident.hw-address = "00:00:5e:00:53:01";
          };
        };
      };

      domains."home.example." = { };

      tsig.keyTpls."kea.router" = {
        algorithm = "hmac-sha256";
        secret = "<SOPS:PLACEHOLDER:PLACEHOLDER>";
      };
      tsig.keaSecrets."kea.router".secret.path = "/dev/null";

      # One rewrite. The attribute name is the `to` suffix, so the entry names `from` and the
      # upstream that answers it. Both suffixes end with a dot, because the option asserts that.
      kresd.rewrites."rewritten.example." = {
        from = "shadow.example.";
        upstreams = [ "198.51.100.10" ];
      };
    };
  };

  nixosWith =
    aspects: extra: (bareNixos (modulesFor "nixos" aspects ++ [ consumer ] ++ extra)).config;

  base = nixosWith [ "net-router" ] [ ];
  dhcpOnly = nixosWith [ "net-router-dhcp" ] [ ];
  ddns = nixosWith [ "net-router-ddns" ] [ ddnsAddr ];
  full =
    nixosWith
      [ "net-router-ddns" "net-router-dns-rewrites" ]
      [
        ddnsAddr
        graph
      ];
  debugOn =
    nixosWith
      [ "net-router-ddns" "net-router-dns-rewrites" ]
      [
        ddnsAddr
        graph
        { kdn.networking.router.debug.all = true; }
      ];

  templateNames = cfg: sorted (builtins.attrNames cfg.kdn.networking.router.templates);
  dhcp4Json = cfg: builtins.fromJSON cfg.kdn.networking.router.templates."kea/dhcp4.conf".content;

  kresdDropIn = "/etc/knot-resolver/kresd.conf.d/50-test-template.conf";
in
{
  assertions = [
    # ---------------------------------------------------------------- the family seam
    {
      name = "the base aspect starts the network stack and no daemon of another aspect";
      expected = {
        nftables = true;
        firewall = true;
        kea4 = false;
        knot = false;
        kresd = false;
        coredns = false;
      };
      actual = {
        nftables = base.networking.nftables.enable;
        firewall = base.networking.firewall.enable;
        kea4 = base.services.kea.dhcp4.enable;
        knot = base.services.knot.enable;
        kresd = base.services.kresd.enable;
        coredns = base.services.coredns.enable;
      };
    }
    {
      name = "the dhcp aspect starts Kea DHCPv4 and no resolver";
      expected = {
        kea4 = true;
        ddns = false;
        knot = false;
        kresd = false;
      };
      actual = {
        kea4 = dhcpOnly.services.kea.dhcp4.enable;
        ddns = dhcpOnly.services.kea.dhcp-ddns.enable;
        knot = dhcpOnly.services.knot.enable;
        kresd = dhcpOnly.services.kresd.enable;
      };
    }
    {
      name = "the ddns aspect pulls in both the dhcp and the dns aspect";
      expected = {
        kea4 = true;
        ddns = true;
        knot = true;
        kresd = true;
        coredns = false;
      };
      actual = {
        kea4 = ddns.services.kea.dhcp4.enable;
        ddns = ddns.services.kea.dhcp-ddns.enable;
        knot = ddns.services.knot.enable;
        kresd = ddns.services.kresd.enable;
        coredns = ddns.services.coredns.enable;
      };
    }
    {
      name = "only the rewrites aspect starts CoreDNS";
      expected = true;
      actual = full.services.coredns.enable;
    }

    # ---------------------------------------------------------------- the templates output
    {
      name = "the base aspect writes one template per net and none of its own";
      expected = [ ];
      actual = templateNames base;
    }
    {
      name = "the dhcp aspect owns the two Kea server configs";
      expected = [
        "kea/dhcp4.conf"
        "kea/dhcp6.conf"
      ];
      actual = templateNames dhcpOnly;
    }
    {
      name = "the ddns aspect adds the Kea DDNS config and the kresd drop-in";
      expected = sorted [
        kresdDropIn
        "kea/dhcp-ddns.conf"
        "kea/dhcp4.conf"
        "kea/dhcp6.conf"
      ];
      actual = templateNames ddns;
    }
    {
      name = "a two-net graph adds one networkd drop-in per net and one key file per TSIG key";
      expected = sorted [
        kresdDropIn
        "/etc/systemd/network/50-lan.network.d/test-50-template.conf"
        "/etc/systemd/network/50-wan.network.d/test-50-template.conf"
        "kea/dhcp-ddns.conf"
        "kea/dhcp4.conf"
        "kea/dhcp6.conf"
        "knot/sops-key.kea.router.conf"
      ];
      actual = templateNames full;
    }
    {
      name = "each template keeps the mode, the path and the reload unit of the old module";
      expected = {
        mode = "0444";
        path = "/run/secrets/rendered/kea/dhcp4.conf";
        reloadUnits = [ "kea-dhcp4-server.service" ];
      };
      actual = {
        inherit (full.kdn.networking.router.templates."kea/dhcp4.conf")
          mode
          path
          reloadUnits
          ;
      };
    }
    {
      name = "Kea reads the rendered path, not a store path";
      expected = "/run/secrets/rendered/kea/dhcp4.conf";
      actual = full.services.kea.dhcp4.configFile;
    }
    {
      name = "no aspect of the family writes a sops option";
      expected = false;
      actual = full ? sops;
    }

    # ---------------------------------------------------------------- the JSON renderer
    {
      name = "the Kea content is plain JSON text, with no import-from-derivation";
      expected = {
        keys = [ "Dhcp4" ];
        subnets = 1;
      };
      actual = {
        keys = builtins.attrNames (dhcp4Json full);
        subnets = builtins.length (dhcp4Json full).Dhcp4.subnet4;
      };
    }
    {
      # Kea reads a pool range with a space on each side of the dash, and the schema renders it that
      # way. The expectation holds the exact string Kea needs.
      name = "the rendered subnet keeps the consumer's subnet id and pool";
      expected = {
        id = 1;
        pool = "198.51.100.100 - 198.51.100.200";
      };
      actual =
        let
          subnet = builtins.head (dhcp4Json full).Dhcp4.subnet4;
        in
        {
          id = subnet.id;
          pool = (builtins.head subnet.pools).pool;
        };
    }

    # ---------------------------------------------------------------- de-personalisation
    {
      name = "the DDNS key id derives from the host name and names no other machine";
      expected = {
        derived = true;
        leaked = false;
      };
      actual =
        let
          text = builtins.toJSON full.services.knot.settings;
        in
        {
          derived = lib.hasInfix "dhcp-ddns:kea.router" text;
          leaked = lib.hasInfix "etra" text;
        };
    }

    # ---------------------------------------------------------------- the three includes
    {
      name = "the family writes three file watchers, one per reloaded daemon";
      expected = [
        "knotd-reload"
        "kresd-reload"
        "systemd-networkd-reload"
      ];
      actual = sorted (builtins.attrNames full.kdn.fs.watch.instances);
    }
    {
      # `kdn.managed.directories` is an `attrsOf`, not a list, so the assertion names the three
      # keys. One key per aspect: the base aspect owns the networkd directory, the DNS aspect the
      # resolver directory and the DDNS aspect the knot directory.
      name = "each aspect adds its own managed directory, and the infix comes from the consumer";
      expected = {
        infix = "test";
        dirs = [
          "/etc/knot-resolver"
          "/etc/knot/knot.conf.d"
          "/etc/systemd/network"
        ];
      };
      actual = {
        infix = full.kdn.managed.infix.kdn-router;
        dirs = sorted (builtins.attrNames full.kdn.managed.directories);
      };
    }
    {
      name = "the secrets target orders every daemon of the family";
      expected = sorted [
        "kdn-knot-init.service"
        "kea-dhcp-ddns-server.service"
        "kea-dhcp4-server.service"
        "knot.service"
        "kresd@.service"
        "systemd-networkd.service"
        "systemd-resolved.service"
      ];
      actual = sorted ddns.systemd.targets.kdn-secrets.wantedBy;
    }

    # ---------------------------------------------------------------- the net graph
    {
      # nixpkgs adds `lo` to this list itself, so an exact list is the wrong probe. The assertion
      # asks about the two interfaces the aspect owns.
      name = "a trusted LAN reaches the firewall, and the uplink does not";
      expected = {
        lan = true;
        wan = false;
      };
      actual = {
        lan = builtins.elem "lan" full.networking.firewall.trustedInterfaces;
        wan = builtins.elem "wan" full.networking.firewall.trustedInterfaces;
      };
    }
    {
      name = "the LAN interface opens the DNS, mDNS and DHCP ports";
      expected = [
        53
        67
        68
        546
        547
        853
        5353
      ];
      actual = sorted full.networking.firewall.interfaces.lan.allowedUDPPorts;
    }

    # ---------------------------------------------------------------- the debug switch
    {
      name = "debug.all turns on both ICMPv6 log tables and the kresd debug level";
      expected = {
        tables = true;
        logLevel = "debug";
      };
      actual = {
        tables = lib.all (n: builtins.elem n (builtins.attrNames debugOn.networking.nftables.tables)) [
          "logging-icpmv6-echo"
          "logging-icpmv6-ndp"
        ];
        logLevel = debugOn.kdn.networking.router.kresd.logLevel;
      };
    }
    {
      name = "debug.all raises the severity of both Kea loggers";
      expected = {
        dhcp4 = "DEBUG";
        ddns = "DEBUG";
      };
      actual = {
        dhcp4 = (builtins.head (dhcp4Json debugOn).Dhcp4.loggers).severity;
        ddns =
          (builtins.head
            (builtins.fromJSON debugOn.kdn.networking.router.templates."kea/dhcp-ddns.conf".content)
            .DhcpDdns.loggers
          ).severity;
      };
    }

    # ---------------------------------------------------------------- the whole system forces
    {
      name = "the full router forces a system closure in a consumer with no sops-nix";
      expected = true;
      actual = builtins.isString full.system.build.toplevel.drvPath;
    }
  ];

  # `den-eval-coverage` reads this table. One row per aspect of the family.
  instantiatedBy = {
    net-router = "den-eval-router (bare nixos, alone and with a two-net graph)";
    net-router-dhcp = "den-eval-router (bare nixos, alone)";
    net-router-dns = "den-eval-router (bare nixos, through the ddns subject)";
    net-router-ddns = "den-eval-router (bare nixos, plain and with a graph)";
    net-router-dns-rewrites = "den-eval-router (bare nixos, with a graph and one rewrite)";
  };
}

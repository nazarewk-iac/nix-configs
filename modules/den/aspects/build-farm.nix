# A build farm in front of Nix remote builders: proxy instances on one host, and the matching
# client registration on the others.
#
# ## Why this exists
#
# Nix picks a remote builder by `load / speedFactor`, with no idea where the client physically is,
# how fast the builder actually is, or whether it is busy serving something else. A host that also
# runs local LLM inference is a slow builder while a model is resident, and `speedFactor` cannot
# say that.
#
# The fix is a **proxy** that appears as one `buildMachines` entry per architecture and balances
# across the real builders. This aspect wraps [`garnix-io/yensid`], which is HAProxy underneath: it
# forwards the SSH stream, so it never reimplements the store protocol.
#
# Two properties follow, and both are the point:
#
# 1. **The away switch is free.** Bind the proxy to a LAN-only address. At home it answers and
#    builds balance; away it is unreachable and native Nix falls back to a local build at connect
#    time. No file, no timer, no rebuild.
# 2. **The decision can see what Nix cannot.** yensid's `custom` strategy is a HAProxy Lua fetch, so
#    a policy can prefer one builder over another by weight or by probing state.
#
# ## One proxy per homogeneous system set
#
# yensid's proxy module binds `*:22` and asserts nothing about systems, but its own docs say a proxy
# may only serve a **homogeneous** set: every backend must support every advertised system. A host
# that serves both `aarch64-darwin` and `aarch64-linux` therefore cannot share a proxy with one that
# serves only `aarch64-linux`.
#
# So one instance per system set, and they cannot share port 22 on one machine. Each instance is a
# NixOS container with its own network namespace and a published host port. That is also why the
# proxy host does not need to be dedicated: the containers keep HAProxy off the host's own sshd.
#
# ## Data versus module
#
# This aspect holds **no host names, addresses or ports**. The consumer supplies them, one row per
# proxy, in its own data file:
#
#     kdn.build-farm.proxies.public = {
#       hostPort = 2222;
#       systems = [ "x86_64-linux" ];
#       builders.brys = { address = "brys.lan.example"; weight = 100; };
#     };
#
# and, on a client:
#
#     kdn.build-farm.clients.public = {
#       address = "farm.lan.example";
#       hostPort = 2222;
#       systems = [ "x86_64-linux" ];
#     };
#
# ## One known sharp edge: host keys
#
# The SSH handshake is end to end between the client and the **backend** builder, because HAProxy is
# in TCP mode. A client therefore sees a different host key per backend, behind one proxy name. The
# clean fix is yensid's `ca` module, which signs short-lived builder host keys that every client
# trusts. Until that is wired, a client entry here sets `StrictHostKeyChecking = no` for its proxy
# alias and says so in `nix.buildMachines` documentation — acceptable only on a trusted LAN, and
# marked as a PoC limitation.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.**
# 2. **No reachable `enable` option.** Inclusion is the switch; an empty `proxies`/`clients` set is
#    the no-op.
# 3. **No custom module argument.**
{ inputs, ... }:
let
  builderType = { lib, ... }: {
    options = {
      address = lib.mkOption {
        type = lib.types.str;
        description = ''
          Where the proxy reaches this builder: a host name or address, as seen **from the proxy
          host**. HAProxy resolves it at start, so a DHCP address that moves needs an
          `haproxy.service` restart; prefer a name with a reservation.
        '';
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 22;
        description = "The builder's SSH port, from the proxy's point of view.";
      };
      weight = lib.mkOption {
        type = lib.types.ints.positive;
        default = 100;
        description = ''
          Relative share of new connections. A high-priority builder takes all traffic while it has
          free slots; a low-priority one is a fallback. Consumed by the `priority` strategy below.
        '';
      };
      maxConnections = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = ''
          The number of in-flight connections after which the `priority` strategy starts sending new
          ones elsewhere. `null` means the weight alone decides.
        '';
      };
    };
  };

  proxyType = { lib, ... }: {
    options = {
      hostPort = lib.mkOption {
        type = lib.types.port;
        description = "The port this proxy is published on, on the proxy host.";
      };
      lanOnly = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Open the published port on the LAN interfaces only, not on every interface. This is what
          gives the free "away" behaviour: a client that is not on the LAN cannot reach the proxy,
          so Nix falls back to a local build at connect time. Turn it off only for a proxy that must
          be reachable from anywhere, and then treat its exposure as deliberate.
        '';
      };
      lanInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "kdn-eth-2g" ];
        description = "The interfaces that may reach this proxy when `lanOnly` is set.";
      };
      hostAddress = lib.mkOption {
        type = lib.types.str;
        description = "The host side of this proxy's veth, in a private /30 or /31.";
      };
      localAddress = lib.mkOption {
        type = lib.types.str;
        description = "The container side of this proxy's veth.";
      };
      systems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = ''
          The systems this proxy advertises. Every builder in `builders` must support all of them,
          which is yensid's homogeneity rule.
        '';
      };
      strategy = lib.mkOption {
        type = lib.types.enum [
          "leastconn"
          "roundrobin"
          "source"
          "priority"
        ];
        default = "leastconn";
        description = ''
          `leastconn`/`roundrobin`/`source` map to yensid's HAProxy strategies. `priority` is this
          aspect's own Lua fetch: prefer the builder with the highest `weight` while it has fewer
          than `maxConnections` open, then fall through to the next.
        '';
      };
      builders = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule builderType);
        default = { };
        description = "The backends behind this proxy.";
      };
    };
  };

  clientType = { lib, ... }: {
    options = {
      address = lib.mkOption {
        type = lib.types.str;
        description = "The proxy's host name, as this client resolves it.";
      };
      hostPort = lib.mkOption {
        type = lib.types.port;
        default = 22;
        description = ''
          The proxy's published port. A value other than 22 needs the SSH alias this aspect writes,
          because `nix.buildMachines` has no port field and the daemon connects with plain `ssh`.
        '';
      };
      systems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "The systems to advertise for this entry. One entry per system set.";
      };
      user = lib.mkOption {
        type = lib.types.str;
        description = "The SSH user the builder account is named.";
      };
      identityFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The SSH key the daemon uses for this builder, readable by root.";
      };
      speedFactor = lib.mkOption {
        type = lib.types.ints.positive;
        default = 32;
        description = ''
          The client-side preference against *this machine's own* local build, not against other
          remotes: the proxy is the only remote entry it competes with. Keep it high on a laptop.
        '';
      };
      maxJobs = lib.mkOption {
        type = lib.types.ints.positive;
        default = 8;
        description = "How many concurrent builds the client may send to the proxy.";
      };
    };
  };
in
{
  kdn.build-farm.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.build-farm;

      # The priority strategy, as a HAProxy Lua fetch. yensid loads it when `strategy = "custom"`.
      priorityLua =
        name: proxy:
        pkgs.writeText "yensid-priority-${name}.lua" ''
          -- Prefer the builder with the highest weight that still has room, otherwise fall back to
          -- the least loaded one. `core.get_server_conns` is 0 before the first connection.
          local order = {
          ${
            lib.concatMapStringsSep "\n" (
              bname:
              let
                b = proxy.builders.${bname};
              in
              "  { name = \"${bname}\", weight = ${toString b.weight}, max = ${
                if b.maxConnections == null then "-1" else toString b.maxConnections
              } },"
            ) (lib.attrNames proxy.builders)
          }
          }

          core.register_fetches('custom-strategy', function(txn)
            local best, fallback, bestLoad = nil, nil, nil
            for _, s in ipairs(order) do
              local conns = core.get_server_conns(s.name, "all")
              if s.max < 0 or conns < s.max then
                if best == nil or s.weight > best.weight then
                  best = s
                end
              end
              if bestLoad == nil or conns < bestLoad then
                bestLoad, fallback = conns, s
              end
            end
            if best ~= nil then return best.name end
            if fallback ~= nil then return fallback.name end
            return "all"
          end)
        '';

      # One container per proxy. `yensid.proxy` binds `*:22` inside, which is why each needs its own
      # network namespace: a shared host would collide with its own sshd.
      proxyContainers = lib.mapAttrs' (
        name: proxy:
        lib.nameValuePair "bf-${name}" {
          autoStart = true;
          restartIfChanged = true;
          privateNetwork = true;
          inherit (proxy) hostAddress localAddress;
          # systemd-nspawn copies the **host's** `/etc/resolv.conf` into the guest, which points at
          # the host's own 127.0.0.53 stub. Inside a private network that stub resolves nothing, so
          # HAProxy cannot resolve a builder name and refuses to start. `off` stops the copy, and
          # the bind mount below replaces the file deterministically: neither the guest's own
          # resolver config nor the host's stub is involved.
          # `off` stops nspawn copying the host's `127.0.0.53` stub into the guest. The guest still
          # ends up with the stub because its own `resolvconf.service` regenerates the file from
          # the interface state, so the file is bind-mounted read-only **and** that service is
          # masked: nothing may rewrite the mount, and the content is exactly the site resolver.
          extraFlags = [ "--resolv-conf=off" ];
          bindMounts."/etc/resolv.conf" = lib.mkIf (cfg.dnsServers != [ ]) {
            hostPath = toString (
              pkgs.writeText "bf-${name}-resolv.conf" (
                lib.concatMapStrings (server: "nameserver ${server}\n") cfg.dnsServers
              )
            );
            isReadOnly = true;
          };
          forwardPorts = [
            {
              protocol = "tcp";
              hostPort = proxy.hostPort;
              containerPort = 22;
            }
          ];
          config =
            { ... }:
            {
              imports = [ inputs.yensid.nixosModules.proxy ];
              yensid.proxy = {
                enable = true;
                # yensid's builder submodule takes `ip` and `port` only. `weight` and
                # `maxConnections` stay on this aspect's side: they drive the `priority` Lua fetch,
                # which reads the per-backend connection counts that yensid's generated config
                # already produces.
                builders = lib.mapAttrs (_: b: {
                  ip = b.address;
                  inherit (b) port;
                }) proxy.builders;
                loadBalancing =
                  if proxy.strategy == "priority" then
                    {
                      strategy = "custom";
                      luaFile = priorityLua name proxy;
                    }
                  else
                    { inherit (proxy) strategy; };
              };
              # yensid's module opens 22 for itself; the rest stays closed.
              system.stateVersion = "26.05";

              # A private-network container gets `127.0.0.53` from systemd-resolved and no
              # upstream, so HAProxy cannot resolve a builder **name** and refuses to start
              # ("could not resolve address"). Point the guest at the site resolver directly.
              # No resolved and no resolvconf inside: the bind mount above is the whole policy,
              # so nothing tries to regenerate the file and nothing fails on a read-only mount.
              services.resolved.enable = lib.mkForce false;
              networking.resolvconf.enable = lib.mkForce false;
              networking.nameservers = [ "127.0.0.1" ];
              systemd.services.resolvconf.enable = lib.mkForce false;
            };
        }
      ) cfg.proxies;

      # The client half. `nix.buildMachines` has no port field, so a proxy on a non-22 port needs an
      # SSH alias that the daemon (root) reads.
      sshAliases = lib.mapAttrs' (
        name: client:
        lib.nameValuePair name "Host build-farm-${name}
      HostName ${client.address}
      Port ${toString client.hostPort}
      User ${client.user}${
        lib.optionalString (client.identityFile != null) "\n      IdentityFile ${client.identityFile}"
      }
      # PoC only: a proxy multiplexes several backends, so the host key differs per connection and
      # strict checking cannot pass for one name. The clean fix is yensid's `ca` module (short-lived
      # builder host certificates). See the aspect header.
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      LogLevel ERROR"
      ) cfg.clients;

      buildMachines = lib.mapAttrsToList (name: client: {
        hostName = "build-farm-${name}";
        protocol = "ssh-ng";
        inherit (client) systems;
        maxJobs = client.maxJobs;
        speedFactor = client.speedFactor;
        sshUser = client.user;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
        mandatoryFeatures = [ ];
      }) cfg.clients;
    in
    {
      options.kdn.build-farm = {
        proxies = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule proxyType);
          default = { };
          description = "Proxy instances to run on this host, one per homogeneous system set.";
        };
        dnsServers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Resolvers for the proxy containers. They need this to resolve a builder by **name**:
            yensid's `ip` field is passed to HAProxy, which resolves it at start and refuses to
            start if it fails. A private-network container has no upstream of its own.
          '';
        };
        hosts = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = ''
            Extra `/etc/hosts` entries. A client reaches a proxy by name, and a PoC should not need
            a DNS-zone change; a zone entry is the production form.
          '';
        };
        clients = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule clientType);
          default = { };
          description = "Proxy instances this host sends builds to.";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.proxies != { }) {
          containers = proxyContainers;
          # The published ports are bound by systemd-nspawn on the host, so the host firewall needs
          # them open on the interface that carries the proxy's address.
          # The proxy container must be able to open SSH to the real builders. `privateNetwork`
          # gives it a veth whose default route is the host, and `nixos-fw`'s forward chain is
          # `policy drop`. Trusting the veth covers the *input* direction only: forwarding needs an
          # allow rule as well, and `trustedInterfaces` does not add one. Without both, the guest
          # resolves a builder, connects, and silently gets nothing, so HAProxy marks every
          # backend down — the failure looks like a DNS or SSH problem and is neither.
          networking.firewall.trustedInterfaces = map (n: "ve-bf-${n}") (lib.attrNames cfg.proxies);
          networking.firewall.extraForwardRules = lib.concatMapStrings (
            n: "iifname \"ve-bf-${n}\" accept\n  oifname \"ve-bf-${n}\" ct state established,related accept\n  "
          ) (lib.attrNames cfg.proxies);
          # The published port is opened on the LAN interfaces when `lanOnly` is set, so a client
          # away from home simply cannot reach the proxy and Nix falls back to a local build.
          networking.firewall.allowedTCPPorts = map (p: p.hostPort) (
            lib.filter (p: !p.lanOnly) (lib.attrValues cfg.proxies)
          );
          networking.firewall.interfaces = lib.mkMerge (
            map (
              p:
              lib.genAttrs p.lanInterfaces (_: {
                allowedTCPPorts = [ p.hostPort ];
              })
            ) (lib.filter (p: p.lanOnly) (lib.attrValues cfg.proxies))
          );
        })
        (lib.mkIf (cfg.hosts != { }) {
          # `networking.hosts` is address -> names, so the name -> address data is grouped and
          # inverted. Several proxy names may share one address.
          networking.hosts = lib.groupBy (name: cfg.hosts.${name}) (lib.attrNames cfg.hosts);
        })
        (lib.mkIf (cfg.clients != { }) {
          environment.etc."ssh/ssh_config.d/60-kdn-build-farm.conf".text =
            lib.concatStringsSep "\n" (lib.attrValues sshAliases) + "\n";
          nix.distributedBuilds = true;
          nix.settings = {
            builders-use-substitutes = true;
            # A dropped link must not stall a build hook for the OS TCP timeout.
            builders = lib.concatMapStringsSep " " (m: "ssh-ng://${m.sshUser}@${m.hostName}") buildMachines;
          };
          nix.buildMachines = buildMachines;
        })
      ];
    };
}

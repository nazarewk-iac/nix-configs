# A Nix build farm: one SSH proxy in front of the fleet's builders.
#
# ## Why a proxy at all
#
# Nix picks a remote builder by `load / speedFactor`, with no idea where the client physically is
# or whether the builder is busy serving something else (`brys` also runs LLM inference). A proxy
# stands in for the fleet, so the client no longer encodes each host, and the away/home switch is
# just "is the proxy reachable".
#
# ## One container, but one port per system set
#
# HAProxy here is a plain L4 (TCP) forwarder: it cannot see which system a Nix build asks for, only
# that an SSH stream opened. So a *single* backend pool that mixes an x86 builder with an arm one
# would send every connection to the first pool member (brys, x86-only) and fail the arm and darwin
# builds. The fleet is heterogeneous, so each **system set gets its own listener port** with its own
# homogeneous backend pool. The client declares one `buildMachines` entry per system set, each
# pointing at that set's port; Nix checks `systems` on the client side, and the port it dials
# selects the matching pool. That is one container, but not one listener.
#
# (`balance` is per connection, so a pool must be homogeneous; the port is what groups it.)
#
# ## Preference is `balance first`, not weights
#
# HAProxy's `first` strategy sends a connection to the first server that has room, in declaration
# order, and only spills to the next when it is full. That is exactly "fast builder first, slow one
# as overflow", with no weight, no Lua, and no fork of yensid. Declare the builders in preference
# order and set `maxconn` on the ones that must not be over-subscribed.
#
# ## Client-side limits
#
# `first` with no `maxconn` never spills: the first server always has room. Each builder's
# `maxconn` is therefore the spill threshold, and it is the only reason a slow builder is ever used.
#
# ## Containment
#
# HAProxy binds a port that a client reaches by name; running it on the host would collide with the
# host's own sshd on 22. So the proxy lives in a NixOS container with a private network, and each
# pool's port is published from the host into it. That also keeps HAProxy off the host's sshd.
#
# ## Not solved here: host keys
#
# A proxy multiplexes backends, so one proxy name presents a different host key per connection.
# Strict host-key checking cannot pass for a single name. yensid's `ca` module (short-lived builder
# certificates) is the correct fix; until it is wired, the client alias for the proxy must relax
# checking, which is only acceptable on a trusted segment.
{ inputs, ... }:
let
  builderType = { lib, ... }: {
    options = {
      address = lib.mkOption {
        type = lib.types.str;
        description = ''
          Where the proxy reaches this builder, as seen from the proxy host. HAProxy resolves it at
          start, so a moving DHCP address needs a `haproxy.service` restart; prefer a reserved name.
        '';
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 22;
        description = "The builder's SSH port, from the proxy's point of view.";
      };
      maxConnections = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = ''
          The spill threshold: once this builder holds this many connections, `balance first` sends
          the next one to the following builder. Without it the first builder is never considered
          full and the rest of the list is dead weight.
        '';
      };
    };
  };

  poolType = { lib, ... }: {
    options = {
      port = lib.mkOption {
        type = lib.types.port;
        description = ''
          The port this pool's listener binds in the container and is published on, on the proxy
          host. One pool per system set, so a client selects the pool by dialling this port.
        '';
      };
      systems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = ''
          The systems this pool serves. Documentation only — the client rows carry the same list and
          Nix checks it there; HAProxy never reads it.
        '';
      };
      builderOrder = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = ''
          The builders of this pool, in preference order. `balance first` walks this list, so the
          order is the policy; an attrset alone has no stable order for that. Every member must be
          able to build the pool's whole `systems` set.
        '';
      };
    };
  };

  proxyType = { lib, ... }: {
    options = {
      hostAddress = lib.mkOption {
        type = lib.types.str;
        description = "The host side of the proxy container's veth.";
      };
      localAddress = lib.mkOption {
        type = lib.types.str;
        description = "The container side of the proxy container's veth.";
      };
      dnsServers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = ''
          The proxy must resolve a builder by **name**, and HAProxy refuses to start when it cannot.
          A private-network container has no upstream of its own, so name the site resolver.
        '';
      };
      builders = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule builderType);
        default = { };
        description = "Every backend a pool may reference, by name. Capped by `maxConnections`.";
      };
      pools = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule poolType);
        default = { };
        description = ''
          One pool per system set, each on its own port. The container exposes each pool as a
          separate L4 listener, so `first` never chooses between builders of different systems.
        '';
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
        description = "The proxy's published port.";
      };
      systems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "One entry per distinct set: Nix only sends a derivation to a matching system.";
      };
      alias = lib.mkOption {
        type = lib.types.str;
        description = ''
          The SSH alias the daemon connects to. `nix.buildMachines` has no port field, so a proxy on
          a port other than 22 must be reached through an alias written by this aspect.
        '';
      };
      user = lib.mkOption {
        type = lib.types.str;
        description = "The SSH account the builder uses.";
      };
      identityFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The builder SSH key, readable by root (the daemon runs the hook).";
      };
      maxJobs = lib.mkOption {
        type = lib.types.ints.positive;
        default = 8;
        description = "Concurrent builds this client sends to the proxy.";
      };
      speedFactor = lib.mkOption {
        type = lib.types.ints.positive;
        default = 16;
        description = ''
          Preference of this proxy entry over the client's **own** local build. It does not rank
          builders against each other — that is the proxy's job.
        '';
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

      # `first` is not in yensid's `loadBalancing.strategy` enum, so the HAProxy config is rendered
      # here and handed to `services.haproxy` directly. That is the only reason this bypasses
      # yensid's module.
      #
      # A `nullOr submodule` option is fragile in a `let`: any attribute read on the null value
      # throws, and `lib.optionalString` evaluates its argument eagerly. So the config is a function
      # of the *resolved* proxy, called only inside the `mkIf` that proves it is not null.
      poolBlock = set: proxy: ''

        frontend ${set}_in
          bind *:${toString proxy.pools.${set}.port}
          default_backend ${set}_out

        backend ${set}_out
          mode tcp
          balance first
          ${lib.concatMapStrings (
            b:
            "server ${b} ${proxy.builders.${b}.address}:${
              toString proxy.builders.${b}.port
            } check inter 10s fall 2 rise 1${
              lib.optionalString (proxy.builders.${b}.maxConnections != null)
                " maxconn ${toString proxy.builders.${b}.maxConnections}"
            }\n  "
          ) proxy.pools.${set}.builderOrder}
      '';
      haproxyConfig = proxy: ''
        global
          daemon

        defaults
          mode tcp
          timeout connect 10s
          timeout client 36h
          timeout server 36h
          option tcp-check
          tcp-check expect rstring SSH-2.0-OpenSSH.*
        ${lib.concatMapStrings (set: poolBlock set proxy) (lib.attrNames proxy.pools)}
      '';

      clients = lib.attrValues cfg.clients;

      # One `nix.buildMachines` entry per client row. The host name must be an SSH alias when the
      # port is not 22: `buildMachines` has no port field and the daemon connects with plain `ssh`.
      sshAliases = lib.concatStringsSep "\n" (
        map (c: ''
          Host ${c.alias}
            HostName ${c.address}
            Port ${toString c.hostPort}
            User ${c.user}${lib.optionalString (c.identityFile != null) "\n  IdentityFile ${c.identityFile}"}
            # PoC: a proxy multiplexes backends, so one name presents several host keys and strict
            # checking cannot pass. yensid's `ca` module is the fix; see the aspect header.
            StrictHostKeyChecking no
            UserKnownHostsFile /dev/null
            LogLevel ERROR
        '') clients
      );
    in
    {
      options.kdn.build-farm = {
        proxy = lib.mkOption {
          type = lib.types.nullOr (lib.types.submodule proxyType);
          default = null;
          description = "Run the build-farm proxy on this host.";
        };
        clients = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule clientType);
          default = { };
          description = "Proxy entries this host sends builds to.";
        };
        localMaxJobs = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          description = ''
            Cap on the host's own parallel local builds. This is the **fallback** path — when the
            proxy is unreachable (away) or a pool is disabled — so it should reflect what the host
            can build without thrashing, not its raw core count. A laptop that thermal-throttles
            wants physical cores, not hyperthreads.
          '';
        };
        hosts = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Extra `/etc/hosts` entries, so a PoC needs no DNS-zone change.";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.hosts != { }) {
          networking.hosts = lib.groupBy (name: cfg.hosts.${name}) (lib.attrNames cfg.hosts);
        })

        (lib.mkIf (cfg.proxy != null) {
          containers.build-farm = {
            autoStart = true;
            restartIfChanged = true;
            privateNetwork = true;
            inherit (cfg.proxy) hostAddress localAddress;
            # nspawn copies the **host's** `/etc/resolv.conf` into the guest. Inside a private
            # network that points at the host's own stub and resolves nothing, and HAProxy refuses
            # to start when it cannot resolve a backend name. `off` stops the copy; the bind mount
            # below supplies the file, and the guest's own resolvers are disabled so nothing tries
            # to rewrite a read-only mount.
            extraFlags = [ "--resolv-conf=off" ];
            bindMounts."/etc/resolv.conf" = {
              hostPath = toString (
                pkgs.writeText "build-farm-resolv.conf" (
                  lib.concatMapStrings (s: "nameserver ${s}\n") cfg.proxy.dnsServers
                )
              );
              isReadOnly = true;
            };
            # One published port per pool; the client dials the port of the system set it wants.
            forwardPorts = lib.mapAttrsToList (set: pool: {
              protocol = "tcp";
              hostPort = pool.port;
              containerPort = pool.port;
            }) cfg.proxy.pools;
            config =
              { ... }:
              {
                services.haproxy = {
                  enable = true;
                  config = haproxyConfig cfg.proxy;
                };
                # The published ports are DNATed by systemd-nspawn to the guest's eth0, so the
                # guest's own input firewall must open them too; the host firewall only gates the
                # publish itself.
                networking.firewall.allowedTCPPorts = lib.mapAttrsToList (set: pool: pool.port) cfg.proxy.pools;
                services.resolved.enable = lib.mkForce false;
                networking.resolvconf.enable = lib.mkForce false;
                networking.nameservers = [ "127.0.0.1" ];
                system.stateVersion = "26.05";
              };
          };

          # `nixos-fw`'s forward chain is `policy drop`. Trusting the veth covers the **input**
          # direction only; forwarding needs its own rule. Without both, the guest resolves a
          # builder, connects, and silently gets nothing, so HAProxy marks every backend down.
          networking.firewall.trustedInterfaces = [ "ve-build-farm" ];
          networking.firewall.extraForwardRules = "iifname \"ve-build-farm\" accept\n  oifname \"ve-build-farm\" ct state established,related accept\n  ";
          networking.firewall.allowedTCPPorts = lib.mapAttrsToList (set: pool: pool.port) cfg.proxy.pools;
        })

        (lib.mkIf (cfg.clients != { }) {
          # `buildMachines`, not `settings.builders`: the latter is a bare URI string that discards
          # `systems`, `maxJobs` and `speedFactor`, and then Nix has no idea which builder can build
          # what. `config` replaces the generated list, so the fleet is not double-listed.
          nix.buildMachines = map (c: {
            hostName = c.alias;
            protocol = "ssh-ng";
            sshUser = c.user;
            inherit (c) systems maxJobs speedFactor;
            supportedFeatures = [
              "nixos-test"
              "benchmark"
              "big-parallel"
              "kvm"
            ];
            mandatoryFeatures = [ ];
          }) (lib.attrValues cfg.clients);
          nix.distributedBuilds = true;
          nix.settings.builders-use-substitutes = true;
          # The fallback is local, but Lix sets no SSH `ConnectTimeout` of its own, so a dropped
          # link (etra down / away from the LAN) stalls the build hook until the OS TCP timeout —
          # minutes — before it gives up and builds locally. These options make an unreachable
          # proxy cost a few seconds. The daemon runs the build hook, so the env goes on the daemon —
          # and on the `nix-daemon@` **template**, because the socket is `Accept=yes` and every
          # client connection spawns a fresh instance from it, not from `nix-daemon.service`.
          systemd.services."nix-daemon@".environment.NIX_SSHOPTS =
            "-o ConnectTimeout=3 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o BatchMode=yes";
          # Cap the local fallback so a thermal-throttled laptop is not asked for every hyperthread.
          nix.settings.max-jobs = lib.mkIf (cfg.localMaxJobs != null) cfg.localMaxJobs;
          # `.config`, not `.conf`: `/etc/ssh/ssh_config` includes `/etc/ssh/ssh_config.d/*.config`,
          # so a `.conf` name is silently ignored and the daemon cannot resolve the alias.
          environment.etc."ssh/ssh_config.d/60-kdn-build-farm.config".text = sshAliases + "\n";
        })
      ];
    };
}

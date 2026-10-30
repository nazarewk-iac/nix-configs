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
{ ... }:
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
      bindAddress = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = ''
          Address the **host** binds the published pool ports to. Set it to the LAN IP so the
          forwarder answers only on the LAN: `away mode` is then free (the LAN name is unreachable
          from elsewhere) and the SSH-banner forwarder never faces the WAN or the mesh. The HAProxy
          inside the container binds `*` on its own veth address; `0.0.0.0` here binds every host
          interface, which is only acceptable behind a firewall that also scopes it.
        '';
      };
      lanInterface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Host interface the pool ports are opened on (`networking.firewall.interfaces.<iface>`).
          A null falls back to a global `allowedTCPPorts`, which opens every interface — prefer a
          name so the WAN/mesh cannot reach the forwarder.
        '';
      };
      remoteBind = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The proxy host's NetBird address, when the pools should also be reachable off the LAN.
          The host firewall opens the pool ports on `meshInterface`, and the DNAT gate lets that
          interface through. With it, an away client reaches the same pools over the mesh. Null
          keeps the forwarder LAN-only.
        '';
      };
      meshInterface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Host interface of the NetBird mesh (for `remoteBind`), e.g. `nb-priv`.";
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
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          A fixed proxy address. Null when `addressLan`/`addressRemote` are given instead, which
          makes the alias pick the reachable path at connect time.
        '';
      };
      addressLan = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "The proxy address that works on the LAN (tried first when set).";
      };
      addressRemote = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The proxy address that works over the NetBird mesh, for when the LAN address does not
          answer. The alias is the same name either way, so the builder list never changes.
        '';
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
      toggleable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          When true, this entry is dropped from the client's builder list while the `brys` switch is
          off — a manual `build-farm-brys off`, or `auto` with none of `autoWifi` in range. This is
          how a client pauses the fast-but-shared x86 builder without touching the proxy: the entry
          names brys alone, so dropping it sends x86 work to the local machine while the arm/darwin
          entries stay. Do not mark an entry that shares its pool with a builder you still want.
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
          # A saturated pool (every server at `maxconn` + `maxqueue`) queues the already-accepted
          # connection; `timeout queue` bounds that wait so ssh fails fast instead of hanging at
          # banner wait (a client's ConnectTimeout cannot fire once HAProxy has accepted).
          timeout queue 10s
          ${lib.concatMapStrings (
            b:
            "server ${b} ${proxy.builders.${b}.address}:${
              toString proxy.builders.${b}.port
            } check inter 10s fall 2 rise 1 maxqueue 2${
              lib.optionalString (proxy.builders.${b}.maxConnections != null)
                " maxconn ${toString proxy.builders.${b}.maxConnections}"
            }\n  "
          ) proxy.pools.${set}.builderOrder}
      '';
      haproxyConfig = proxy: ''
        defaults
          mode tcp
          timeout connect 10s
          timeout client 36h
          timeout server 36h
          option tcp-check
          tcp-check expect rstring SSH-2.0-OpenSSH.*
        ${lib.concatMapStrings (set: poolBlock set proxy) (lib.attrNames proxy.pools)}
      '';

      # Interfaces the pool ports are reachable on: the LAN, plus the NetBird mesh when
      # `remoteBind` is set. Computed here because the proxy is the only host that has pools.
      reachableInterfaces =
        if cfg.proxy == null then
          [ ]
        else
          lib.filter (i: i != null) [
            cfg.proxy.lanInterface
            (if cfg.proxy.remoteBind != null then cfg.proxy.meshInterface else null)
          ];

      clients = lib.attrValues cfg.clients;

      # Legacy `@/etc/nix/machines` line format, one per client row. `nix.buildMachines` cannot be
      # toggled at run time (it is a store path), so the client list is a plain file the daemon
      # re-reads per derivation, and the on|off switch just rewrites that file.
      features = [
        "nixos-test"
        "benchmark"
        "big-parallel"
        "kvm"
      ];
      machineLine =
        c:
        "ssh-ng://${c.user}@${c.alias} ${lib.concatStringsSep "," c.systems} - ${toString c.maxJobs} ${toString c.speedFactor} ${lib.concatStringsSep "," features} - -";
      machinesOn = lib.concatMapStrings (c: machineLine c + "\n") clients;
      machinesOff = lib.concatMapStrings (c: machineLine c + "\n") (
        builtins.filter (c: !c.toggleable) clients
      );

      # One `nix.buildMachines` entry per client row. The host name must be an SSH alias when the
      # port is not 22: `buildMachines` has no port field and the daemon connects with plain `ssh`.
      # One alias per client row. When both `addressLan` and `addressRemote` are set, the alias picks
      # the reachable path at connect time with `Match exec`: try the LAN name with a short connect
      # probe, fall back to the NetBird name. The alias name never changes, so the builder file
      # (`/run/kdn/nix-machines`) does not have to be rewritten when you move between home and away.
      aliasBlock = c: ''
        Host ${c.alias}
          Port ${toString c.hostPort}
          User ${c.user}${lib.optionalString (c.identityFile != null) "\n  IdentityFile ${c.identityFile}"}
          # A proxy multiplexes backends, so one name presents several host keys and strict checking
          # cannot pass. yensid's `ca` module is the fix; see the aspect header.
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
          LogLevel ERROR
          # Pick the reachable path. ssh applies the **first** `HostName` and ignores later ones, so
          # the condition must guard the LAN value, with the remote value as the unconditional
          # default. `Match originalhost` matches the name as typed (the alias); the exec probe tests
          # the LAN name with a 1 s connect. A fixed `address` skips both.
        ${
          if c.address != null then
            "  HostName ${c.address}"
          else
            ''
              Match originalhost ${c.alias} exec "nc -z -w1 ${c.addressLan} ${toString c.hostPort} 2>/dev/null"
                HostName ${c.addressLan}
              Match originalhost ${c.alias}
                HostName ${c.addressRemote}''
        }
      '';
      sshAliases = lib.concatStringsSep "\n" (map aliasBlock clients);
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
        autoWifi = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Wi-Fi SSIDs that mean "the fast x86 builder is worth using here". In `auto` mode the
            `build-farm-brys` switch is on when any of these is in range (shown by `nmcli`, whether
            or not this host is connected to it), and off otherwise. Empty means `auto` is always
            on — there is nothing to gate on.
          '';
        };
        reachProbe = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            An SSH destination (user@host) whose reachability also counts as "home" in `auto` mode,
            tested with `ssh -o ConnectTimeout=2 … true`. It catches the case the Wi-Fi check misses:
            at home on wired ethernet, or with the Wi-Fi radio off. Null disables it.
          '';
        };
        hosts = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Extra `/etc/hosts` entries, so a PoC needs no DNS-zone change.";
        };
      };

      config = lib.mkMerge [
        # A client's `hostPort`+`systems` must name a pool on the proxy, or it silently talks to the
        # wrong pool (HAProxy never checks `systems`; the client carries it). Only a host that runs
        # BOTH the proxy and the clients can be checked, since pools are local data.
        (lib.mkIf (cfg.proxy != null && cfg.clients != { }) {
          assertions = [
            {
              assertion = builtins.all (
                c: builtins.any (p: p.port == c.hostPort && p.systems == c.systems) (lib.attrValues cfg.proxy.pools)
              ) clients;
              message = "kdn.build-farm: every client hostPort/systems must match one proxy pool's port/systems.";
            }
          ];
        })

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
            # Bind the host side to `bindAddress` (normally the LAN IP), so the forwarder answers
            # only there regardless of the firewall.
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
                # The container has nothing to run but HAProxy; a full `nix` pulls in a daemon and
                # subuid/subgid ranges for no reason.
                nix.enable = lib.mkForce false;
                system.stateVersion = "26.05";
              };
          };

          # `nixos-fw`'s forward chain is `policy drop`. Trusting the veth covers the **input**
          # direction only; forwarding needs its own rule. Without both, the guest resolves a
          # builder, connects, and silently gets nothing, so HAProxy marks every backend down.
          networking.firewall.trustedInterfaces = [ "ve-build-farm" ];
          networking.firewall.extraForwardRules = "iifname \"ve-build-farm\" accept\n  oifname \"ve-build-farm\" ct state established,related accept\n  ";
          # Open the published pool ports on the LAN interface only. A global `allowedTCPPorts`
          # would expose the forwarder on the WAN and the NetBird mesh too, which both leaks the
          # builder banner to the internet and defeats the "away ⇒ local" invariant.
          #
          # `networking.firewall.interfaces` alone is NOT enough: systemd-nspawn's `forwardPorts`
          # installs its own interface-agnostic DNAT (`fib daddr type local dnat … map_port_ipport`)
          # in `prerouting`, which rewrites a packet **before** the filter chain, so the input-chain
          # accept never sees the interface. Drop the pool ports early on every non-LAN interface, at
          # a higher nft priority than nspawn's `dstnat + 1`, so the DNAT never runs for them.
          # The pool ports are reachable on the LAN, and — when `remoteBind` is set — on the NetBird
          # mesh too (an away client then reaches the same pools). Nothing else: the WAN never sees
          # them.
          networking.firewall.interfaces = lib.genAttrs reachableInterfaces (_: {
            allowedTCPPorts = lib.mapAttrsToList (set: pool: pool.port) cfg.proxy.pools;
          });
          networking.firewall.allowedTCPPorts = lib.mkIf (reachableInterfaces == [ ]) (
            lib.mapAttrsToList (set: pool: pool.port) cfg.proxy.pools
          );
          networking.nftables.tables."kdn-bf-gate" = lib.mkIf (reachableInterfaces != [ ]) {
            family = "inet";
            # nspawn's DNAT runs at `dstnat + 1` (-99); be earlier so the packet is dropped before
            # the DNAT can rewrite an arrival on a non-reachable interface onto the container.
            content = ''
              chain prerouting {
                type filter hook prerouting priority -101; policy accept;${
                  lib.concatMapStrings (
                    port:
                    "\n  iifname != { ${
                      lib.concatStringsSep ", " (map (i: "\"${i}\"") reachableInterfaces)
                    } } tcp dport ${toString port} drop"
                  ) (lib.mapAttrsToList (set: pool: pool.port) cfg.proxy.pools)
                }
              }
            '';
          };
        })

        (lib.mkIf (cfg.clients != { }) {
          # The builder list is a plain file the daemon re-reads per derivation, so the `brys`
          # switch (`build-farm-brys on|off`) needs no rebuild and no daemon restart. `builders`
          # names that file; `nix.buildMachines` is deliberately not used, because it resolves to a
          # store path fixed at build time.
          nix.settings.builders = lib.mkForce "@/run/kdn/nix-machines";
          nix.distributedBuilds = true;
          nix.settings.builders-use-substitutes = true;
          # The fallback is local, but Lix sets no SSH `ConnectTimeout` of its own, so a dropped
          # link (etra down / away from the LAN) stalls the build hook until the OS TCP timeout —
          # minutes — before it gives up and builds locally. A short connect timeout makes an
          # unreachable proxy cost a few seconds. `ServerAlive*` is deliberately **off** on the
          # long-lived side: a transient stall on Wi-Fi must not kill a build, which native Nix
          # cannot retry. The env goes on the `nix-daemon@` **template**, because the socket is
          # `Accept=yes` and every client connection spawns a fresh instance from it.
          systemd.services."nix-daemon@".environment.NIX_SSHOPTS = "-o ConnectTimeout=8 -o BatchMode=yes";
          # Cap the local fallback so a thermal-throttled laptop is not asked for every hyperthread.
          nix.settings.max-jobs = lib.mkIf (cfg.localMaxJobs != null) cfg.localMaxJobs;
          # `.config`, not `.conf`: `/etc/ssh/ssh_config` includes `/etc/ssh/ssh_config.d/*.config`,
          # so a `.conf` name is silently ignored and the daemon cannot resolve the alias.
          environment.etc."ssh/ssh_config.d/60-kdn-build-farm.config".text = sshAliases + "\n";

          # The switch has a *mode* (`auto` by default, or a manual `on`/`off`) and an *effective*
          # state. In `auto` the effective state is on when one of `autoWifi` is in range and off
          # otherwise; a manual `on`/`off` overrides it. The generator recomputes the effective state
          # and rewrites the builder file from one of two embedded lists; a timer re-runs it, so
          # `auto` follows the Wi-Fi with no manual step.
          systemd.services.kdn-build-farm-machines = {
            description = "Recompute the build-farm builder list from the brys on|off|auto state";
            wantedBy = [ "multi-user.target" ];
            before = [
              "nix-daemon.service"
              "nix-daemon.socket"
            ];
            path = [
              pkgs.networkmanager
              pkgs.gnugrep
              pkgs.gnused
              pkgs.coreutils
              pkgs.openssh
            ];
            serviceConfig.Type = "oneshot";
            environment = {
              MACHINES_ON = toString (pkgs.writeText "kdn-nix-machines-on" machinesOn);
              MACHINES_OFF = toString (pkgs.writeText "kdn-nix-machines-off" machinesOff);
              # One SSID per line, so a name with spaces survives (`while read`, not word-split).
              AUTO_SSIDS = lib.concatMapStrings (s: s + "\n") cfg.autoWifi;
              # Optional reachability fallback: when set, "is brys reachable on the LAN" also
              # counts as home, so ethernet-with-the-radio-off is not mistaken for away.
              REACH_PROBE = cfg.reachProbe;
            };
            script = ''
              set -eu
              dir=/var/lib/kdn/build-farm
              install -d -m 0755 "$dir" /run/kdn
              mode=$(cat "$dir/mode" 2>/dev/null || echo auto)
              case "$mode" in
                on) eff=on ;;
                off) eff=off ;;
                *)
                  # auto (and any unknown value): on when a listed SSID is in range, or when the
                  # reachability probe (if configured) succeeds. A scan failure leans off, which is
                  # the safe direction (local build still works).
                  eff=off
                  nmcli device wifi rescan >/dev/null 2>&1 || true
                  sleep 2
                  list=$(nmcli --terse --fields SSID device wifi list 2>/dev/null || true)
                  while IFS= read -r s; do
                    [ -n "$s" ] || continue
                    if printf '%s\n' "$list" | grep -Fxq -- "$s"; then eff=on; break; fi
                  done <<EOF
              $AUTO_SSIDS
              EOF
                  if [ "$eff" = off ] && [ -n "$REACH_PROBE" ]; then
                    if ssh -o ConnectTimeout=2 -o BatchMode=yes -o StrictHostKeyChecking=no \
                         -o UserKnownHostsFile=/dev/null "$REACH_PROBE" true >/dev/null 2>&1; then
                      eff=on
                    fi
                  fi
                  ;;
              esac
              printf '%s\n' "$eff" > "$dir/effective"
              if [ "$eff" = on ]; then src="$MACHINES_ON"; else src="$MACHINES_OFF"; fi
              # Atomic: a build hook re-reading this must never see a half-written file.
              install -m 0644 "$src" "$dir/nix-machines.tmp"
              mv -f "$dir/nix-machines.tmp" /run/kdn/nix-machines
            '';
          };

          systemd.timers.kdn-build-farm-machines = {
            description = "Track the Wi-Fi for the brys auto switch";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "1min";
              OnUnitActiveSec = "2min";
            };
          };

          environment.systemPackages = [
            (pkgs.writeShellScriptBin "build-farm-brys" ''
              set -eu
              [ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
              dir=/var/lib/kdn/build-farm
              install -d -m 0755 "$dir"
              show() {
                m=$(cat "$dir/mode" 2>/dev/null || echo auto)
                e=$(cat "$dir/effective" 2>/dev/null || echo on)
                if [ "$m" = auto ]; then printf '%s\n' "$e-auto"; else printf '%s\n' "$e"; fi
              }
              case "''${1:-status}" in
                on | off | auto)
                  printf '%s\n' "''${1}" > "$dir/mode"
                  systemctl restart kdn-build-farm-machines.service
                  ;;
                status)
                  show
                  exit 0
                  ;;
                *)
                  echo "usage: build-farm-brys on|off|auto|status" >&2
                  exit 2
                  ;;
              esac
              show
            '')
          ];
        })
      ];
    };
}

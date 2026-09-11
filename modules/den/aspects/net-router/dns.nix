# The `net-router-dns` aspect target: the kresd recursive resolver.
#
# It is one target module of the `net-router` aspect family. ./net-router.nix declares the family
# and ../README.md states the rules.
#
# ## What it holds
#
# | Concern | Old line range |
# |---|---|
# | the `kresd.{logLevel,interfaces,localAddress}` options | 642-660 |
# | the `kresd.defaultUpstream` and `kresd.upstreams` options | 698-769 |
# | `debug.kresd` raises the kresd log level | 879-881 |
# | the `/etc/knot-resolver` cleanup entry | 942-954 |
# | the kresd package override, the Lua payload, the reload watcher, two persist buckets | 1083-1145 |
# | the generated Lua policy, the drop-in template, `Restart=on-failure` | 1146-1259 |
# | the default upstream, gated on `defaultUpstream != null` | 1781-1829 |
#
# ## What the port changes
#
# 1. S1: the file writes a plain `config = lib.mkMerge [ … ]`. Inclusion is the switch now.
# 2. S2: `kdn.env.packages` becomes `environment.systemPackages`.
# 3. S7: the kresd drop-in template goes to `kdn.networking.router.templates`. A consumer renders it.
# 4. S12: the two persist buckets stay, so the file imports the persist option.
# 5. S13: the `debug.kresd` guard stays verbatim.
# 6. The cleanup list splits three ways. This file adds only the `/etc/knot-resolver` entry.
# 7. It reads the Lua payload from `./kresd.conf.lua`, a byte copy next to this file.
# 8. It replaces one host name in a comment with the generic name `router`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kdn.networking.router;
in
{
  imports = [
    ../../common/host-name.nix
    ../../common/persist.nix
  ];

  options.kdn.networking.router = {
    kresd.logLevel = lib.mkOption {
      type =
        with lib.types;
        enum [
          "info"
          "debug"
        ];
      default = "info";
    };

    kresd.interfaces = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };

    kresd.localAddress = lib.mkOption {
      type = with lib.types; str;
      default = "127.0.0.3";
    };

    kresd.defaultUpstream = lib.mkOption {
      type =
        with lib.types;
        nullOr (enum [
          "systemd-resolved"
          "google"
          "cloudflare"
          "quad9"
        ]);
      default = "systemd-resolved";
    };

    kresd.upstreams = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule (upstreamArgs: {
          options = {
            enable = lib.mkOption {
              type = with lib.types; bool;
              default = true;
            };
            description = lib.mkOption {
              type = with lib.types; str;
            };
            nameservers = lib.mkOption {
              type = with lib.types; listOf str;
            };
            nameserversRaw = lib.mkOption {
              type = with lib.types; listOf str;
              default = [ ];
            };
            domains = lib.mkOption {
              type = with lib.types; nullOr (listOf str);
              default = null;
              apply =
                domains:
                let
                  invalids = builtins.filter (domain: !(lib.strings.hasSuffix "." domain)) domains;
                in
                assert lib.assertMsg (domains == null || invalids == [ ]) ''
                  `kdn.networking.router.kresd.upstreams.*.domains` must end with a '.', invalid entries: ${builtins.concatStringsSep ", " invalids}
                '';
                domains;
            };
            type = lib.mkOption {
              type =
                with lib.types;
                enum [
                  "STUB"
                  "FORWARD"
                  "TLS_FORWARD"
                ];
            };
            flags = lib.mkOption {
              type =
                with lib.types;
                listOf (enum [
                  # see https://knot-resolver.readthedocs.io/en/stable/lib.html#c.kr_qflags
                  "NO_IPV6"
                  "NO_EDNS"
                  "NO_0X20" # DNS lettercase randomization
                  "NO_CACHE"
                ]);
              default = [ ];
            };
            auth = lib.mkOption {
              type = with lib.types; attrsOf str;
              default = { };
            };
          };
        })
      );
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.debug.kresd {
      kdn.networking.router.kresd.logLevel = "debug";
    })
    {
      # cleaning up managed files
      kdn.managed.directories = [
        "/etc/knot-resolver"
      ];
    }
    {
      # kresd DNS resolver
      environment.systemPackages = [
        config.services.knot.package # contains `kdig`
      ];
      services.kresd.enable = true;
      services.kresd.listenPlain = [ ];
      services.kresd.package =
        (pkgs.knot-resolver_5.override {
          extraFeatures = true;
        }).overrideAttrs
          (old: {
            buildInputs =
              old.buildInputs
              ++ (with pkgs.luajitPackages; [
                luafilesystem
              ]);
          });
      kdn.networking.router.kresd.interfaces = lib.pipe cfg.nets [
        builtins.attrValues
        (builtins.filter (netCfg: netCfg.type == "lan"))
        (map (netCfg: netCfg.interface))
      ];

      # logging functions are available at https://gitlab.nic.cz/knot/knot-resolver/-/blob/v5.7.4/daemon/lua/sandbox.lua.in#L63
      services.kresd.extraConfig = builtins.readFile ./kresd.conf.lua;
      systemd.services."kresd@".environment.KRESD_CONF_DIR = "/etc/knot-resolver";

      # copy dependencies over from `kea-dhcp4-server.service`
      systemd.services."kresd@".after = [
        "network-online.target"
        "time-sync.target"
      ];
      systemd.services."kresd@".wants = [
        "network-online.target"
      ];

      kdn.fs.watch.instances.kresd-reload.files = [
        "/etc/knot-resolver"
      ];
      kdn.fs.watch.instances.kresd-reload.exec = [
        (lib.getExe' pkgs.systemd "systemctl")
        "reload-or-restart"
      ]
      ++ map (i: "kresd@${toString i}.service") (lib.lists.range 1 config.services.kresd.instances);

      kdn.disks.persist."sys/data".directories = [
        {
          directory = "/var/lib/knot-resolver";
          user = "knot-resolver";
          group = "knot-resolver";
          mode = "0770";
        }
      ];
      kdn.disks.persist."sys/cache".directories = [
        {
          directory = "/var/cache/knot-resolver";
          user = "knot-resolver";
          group = "knot-resolver";
          mode = "0770";
        }
      ];
    }
    {
      services.kresd.extraConfig =
        lib.pipe
          [
            "log_level(${builtins.toJSON cfg.kresd.logLevel})"
            (lib.pipe cfg.kresd.upstreams [
              (map (
                upstreamCfg:
                let
                  toLuaTable =
                    value:
                    lib.pipe value [
                      (builtins.concatStringsSep ", ")
                      (e: "{${e}}")
                    ];
                  toLuaStringList = list: toLuaTable (map builtins.toJSON list);
                  authArgsList = lib.attrsets.mapAttrsToList (
                    key: value: "${key}=${builtins.toJSON value}"
                  ) upstreamCfg.auth;

                  nameserverEntries = upstreamCfg.nameserversRaw ++ map builtins.toJSON upstreamCfg.nameservers;
                  tlsNameserversArg = lib.pipe nameserverEntries [
                    (map (
                      ns:
                      lib.pipe ns [
                        (ns: [ ns ] ++ authArgsList)
                        (prev: if builtins.length prev > 1 then toLuaTable prev else builtins.head prev)
                      ]
                    ))
                    toLuaTable
                  ];
                  domainsArg = lib.pipe upstreamCfg.domains [
                    (map builtins.toJSON)
                    toLuaTable
                  ];
                  descriptionSnippet = lib.pipe upstreamCfg.description [
                    (lib.strings.splitString "\n")
                    (map (line: "-- ${line}"))
                    (builtins.concatStringsSep "\n")
                  ];
                  policyFilter = if upstreamCfg.domains == null then "all" else "suffix";
                  actionArgs =
                    if upstreamCfg.type == "TLS_FORWARD" then tlsNameserversArg else toLuaTable nameserverEntries;

                  domainPolicyArgs = lib.lists.optional (
                    upstreamCfg.domains != null
                  ) "policy.todnames(${domainsArg})";
                in
                builtins.concatStringsSep "\n" (
                  [
                    descriptionSnippet
                  ]
                  ++ lib.optionals (upstreamCfg.flags != [ ]) [
                    "policy.add(policy.${policyFilter}("
                    (builtins.concatStringsSep ", " (
                      [ "  policy.FLAGS(${toLuaStringList upstreamCfg.flags})" ] ++ domainPolicyArgs
                    ))
                    "))"
                  ]
                  ++ lib.optionals (nameserverEntries != [ ]) [
                    "policy.add(policy.${policyFilter}("
                    (builtins.concatStringsSep ", " (
                      [ "  policy.${upstreamCfg.type}(${actionArgs})" ] ++ domainPolicyArgs
                    ))
                    "))"
                  ]
                )
              ))
            ])
            "net.listen(${builtins.toJSON cfg.kresd.localAddress}, 53, { kind = 'dns', freebind = true })"
            /*
              TODO: On 2025-09-14 10:09:51 neither `kresd@{1,2}` nor `kea-dhcp4-server` were listening on the LAN interface's (bridge) IP address after power failure
                it was caused by networkd activating the target even after this error occurred:
                    Sep 14 10:09:41 router systemd-networkd[1199]: lan: Failed to get link from ifindex 6, ignoring: No such device
                the interface was configured a few seconds later.
                Neither kresd (confirmed) nor kea (probably?) listens for IP addressing changes on the interfaces
                It could be addressed by either:
                  - restarting both kresd and kea (to pick up new IPs) upon changes to addressing
                  - listening directly on the IP addresses, they don't need to be available due to `freebind = true`.
            */
            (map (
              iface: "net.listen(net[${builtins.toJSON iface}], 53, { kind = 'dns', freebind = true })"
            ) cfg.kresd.interfaces)
          ]
          [
            lib.lists.flatten
            lib.mkMerge
          ];
      kdn.networking.router.templates =
        let
          _path = "/etc/knot-resolver/kresd.conf.d/50-${cfg.dropin.infix}-template.conf";
        in
        {
          "${_path}" = {
            path = _path;
            mode = "0640";
            owner = "knot-resolver";
            group = "knot-resolver";
            content =
              lib.pipe
                [
                ]
                [
                  lib.lists.flatten
                  (builtins.concatStringsSep "\n")
                ];
          };
        };
      systemd.services."kresd@".serviceConfig = {
        # seems like kresd can come up before the interface is ready for listening during reconfigurations
        Restart = "on-failure";
        RestartSec = 1;
      };
    }
    (lib.mkIf (cfg.kresd.defaultUpstream != null) {
      kdn.networking.router.kresd.upstreams =
        let
          upstreams = {
            systemd-resolved = {
              # TODO: those queries seem to time out a lot
              description = "systemd-resolved";
              type = "STUB";
              nameservers = [ "127.0.0.53" ];
            };
            quad9 = {
              description = "Quad9";
              type = "TLS_FORWARD";
              nameservers = [
                "2620:fe::fe"
                "2620:fe::10"
                "9.9.9.9"
                "9.9.9.10"
              ];
              auth.hostname = "dns.quad9.net";
            };
            cloudflare = {
              description = "Cloudflare";
              type = "TLS_FORWARD";
              nameservers = [
                "2606:4700:4700::1111"
                "2606:4700:4700::1001"
                "1.1.1.1"
                "1.0.0.1"
              ];
              auth.hostname = "cloudflare-dns.com";
            };
            google = {
              description = "Google";
              type = "TLS_FORWARD";
              auth.hostname = "dns.google";
              nameservers = [
                "2001:4860:4860::8888"
                "2001:4860:4860::8844"
                "8.8.8.8"
                "8.8.4.4"
              ];
            };
          };
        in
        lib.mkAfter [
          upstreams."${cfg.kresd.defaultUpstream}"
        ];
    })
  ];
}

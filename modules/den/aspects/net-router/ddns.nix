# The authoritative knot server, the TSIG keys and the Kea-to-Knot DDNS bridge.
#
# It is one target module of the `net-router` aspect family. ./net-router.nix declares the family
# and ../README.md states the rules.
#
# ## What it holds
#
# | Concern | Old line range |
# |---|---|
# | The two knot shell wrappers, in the `let` block | 36-70 |
# | `addr.public.ipv4.path`, `addr.public.ipv6.path` | 505-510 |
# | `kea.dhcp-ddns.settings` | 540-543 |
# | `domains` | 564-586 |
# | The six `knot.*` options | 593-635 |
# | `tsig.keaSecrets`, `tsig.keyTpls` | 770-795 |
# | The `cfg.knot.configDir` cleanup entry | 942-954 |
# | The Kea DHCP-DDNS config file | 1047-1058 |
# | knot, the ACLs, the zones, the TSIG templates and `kdn-knot-init` | 1260-1555 |
#
# ## What the port changes
#
# 1. S1 — the `config` head becomes a plain `lib.mkMerge`. Inclusion is the switch.
# 2. S3 — three ACL literals held one real machine name. Each one now reads
#    `"dhcp-ddns:${keaTSIGName}"`, so the file holds no host name.
# 3. S4 — the DDNS wrapper took a package of the old tree. It now reads the new
#    `knot.ddns.secretsRenderer` option, whose default is a pass-through shim.
# 4. S5 — `kea.dhcp-ddns.settings` reads its type from ./json-template.nix, so it needs no overlay.
# 5. S6 — the Kea DHCP-DDNS file calls `jsonTemplate.generateText`, so it builds no derivation
#    during the evaluation.
# 6. S7 and S8 — each secret-bearing file goes to `kdn.networking.router.templates`, and each read
#    of a rendered path goes to `cfg.templates`.
# 7. S12 — the knot data directory keeps its `kdn.disks.persist."sys/data"` entry, so this file
#    imports the persist aspect.
# 8. The cleanup list of old 942-954 splits three ways. This file adds the `cfg.knot.configDir`
#    entry only.
# 9. The two wrapper payloads move next to this file, so each `builtins.readFile` reads a plain
#    relative path.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kdn.networking.router;
  schema = import ./schema.nix { inherit config lib pkgs; };
  inherit (schema)
    keaTSIGName
    ;
  jsonTemplate = import ./json-template.nix { inherit lib pkgs; };

  kdn-router-knot-setup-zone = pkgs.writeShellApplication {
    name = "kdn-router-knot-setup-zone";
    runtimeInputs = [
      config.services.knot.package
    ]
    ++ (with pkgs; [
      coreutils
      gnused
    ]);
    # `tsig.keyTpls` defaults to `{ }`, and the template set below then holds no `knot/sops-key.*`
    # entry. `or` keeps this wrapper evaluable for a tree that holds no key.
    runtimeEnv.TSIG_KEY_PATH = cfg.templates."knot/sops-key.admin.conf".path or "/dev/null";
    runtimeEnv.KNOT_ADDR = cfg.knot.localAddress;
    runtimeEnv.KNOT_PORT = toString cfg.knot.localPort;
    runtimeEnv.PUBLIC_IPV4_PATH = cfg.addr.public.ipv4.path;
    runtimeEnv.PUBLIC_IPV6_PATH = cfg.addr.public.ipv6.path;
    text = builtins.readFile ./kdn-router-knot-setup-zone.sh;
  };

  kdn-router-knot-ddns-update = pkgs.writeShellApplication {
    name = "kdn-router-knot-ddns-update";
    runtimeInputs = [
      config.services.knot.package
    ]
    ++ (with pkgs; [
      coreutils
      gnused
      cfg.knot.ddns.secretsRenderer
    ]);
    # Same reason as the wrapper above: an empty `tsig.keyTpls` gives no template.
    runtimeEnv.TSIG_KEY_PATH = cfg.templates."knot/sops-key.admin.conf".path or "/dev/null";
    runtimeEnv.KNOT_ADDR = cfg.knot.localAddress;
    runtimeEnv.KNOT_PORT = toString cfg.knot.localPort;
    text = builtins.readFile ./kdn-router-knot-ddns-update.sh;
  };
in
{
  imports = [
    ../../common/host-name.nix
    ../../common/persist.nix
  ];

  options.kdn.networking.router = {
    addr.public.ipv4.path = lib.mkOption {
      type = with lib.types; path;
    };
    addr.public.ipv6.path = lib.mkOption {
      type = with lib.types; path;
    };

    kea.dhcp-ddns.settings = lib.mkOption {
      type = jsonTemplate.type;
      default = { };
    };

    domains = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }@domainArgs:
          {
            options = {
              name = lib.mkOption {
                readOnly = true;
                type = with lib.types; str;
                default = domainArgs.name;
                apply =
                  domain:
                  assert lib.assertMsg (lib.strings.hasSuffix "." domain) ''
                    `kdn.networking.router.domains` must end with a '.', invalid enty: ${domain}
                  '';
                  domain;
              };
            };
          }
        )
      );
      default = { };
    };

    knot.localAddress = lib.mkOption {
      type = with lib.types; str;
      default = "127.0.0.1";
    };
    knot.localPort = lib.mkOption {
      type = with lib.types; port;
      default = 53;
    };
    knot.localPortTLS = lib.mkOption {
      type = with lib.types; port;
      default = 853;
    };

    knot.listens = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      apply =
        value:
        lib.pipe value [
          (
            v:
            [
              (
                if cfg.knot.localPort == 53 then
                  cfg.knot.localAddress
                else
                  "${cfg.knot.localAddress}@${toString cfg.knot.localPort}"
              )
            ]
            ++ v
          )
          lib.lists.unique
        ];
    };

    knot.configDir = lib.mkOption {
      type = with lib.types; path;
      default = "/etc/knot/knot.conf.d";
    };
    knot.dataDir = lib.mkOption {
      type = with lib.types; path;
      default = "/var/lib/knot";
    };

    knot.ddns.secretsRenderer = lib.mkOption {
      description = ''
        The program that resolves a secret placeholder inside a DDNS record value. The DDNS update
        wrapper calls it as `kdn-sops-secrets render-string <value>`, so the package must install a
        binary of that name.

        The default is a pass-through shim: it prints the value unchanged. That is correct for every
        reachable input, because `kdn-knot-init` already drops each zone entry whose value still
        holds an unresolved marker. A consumer that renders a real secret sets its own package here.
      '';
      type = lib.types.package;
      default = pkgs.writeShellApplication {
        name = "kdn-sops-secrets";
        text = ''
          # A pass-through shim. `render-string` prints its argument with no change.
          case "''${1:-}" in
          render-string)
            shift
            printf '%s' "''${1:-}"
            ;;
          *)
            echo "kdn-sops-secrets: this shim serves render-string only" >&2
            exit 2
            ;;
          esac
        '';
      };
      defaultText = lib.literalExpression "a pass-through shim that prints the value unchanged";
    };

    tsig.keaSecrets = lib.mkOption {
      default = { };
    };
    tsig.keyTpls = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              name = lib.mkOption {
                type = with lib.types; str;
                default = name;
              };

              algorithm = lib.mkOption {
                type = with lib.types; str;
              };
              secret = lib.mkOption {
                type = with lib.types; str;
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkMerge [
    {
      # cleaning up managed files
      kdn.managed.directories = [
        cfg.knot.configDir
      ];
    }
    {
      kdn.networking.router.templates."kea/dhcp-ddns.conf" = {
        mode = "0444";
        reloadUnits = [ "kea-dhcp-ddns-server.service" ];
        content = jsonTemplate.generateText {
          DhcpDdns = cfg.kea.dhcp-ddns.settings;
        };
      };
      services.kea.dhcp-ddns.configFile = cfg.templates."kea/dhcp-ddns.conf".path;
    }
    (
      let
        d2Domains = lib.pipe cfg.nets [
          (lib.attrsets.mapAttrsToList (_: netCfg: netCfg.domain))
          lib.lists.unique
          (builtins.sort builtins.lessThan)
        ];
      in
      {
        # knot-dns
        services.knot.enable = true;
        services.knot.checkConfig = false; # doesn't allow some stuff like referencing keys
        kdn.fs.watch.instances.knotd-reload.dirs = [ cfg.knot.configDir ];
        kdn.fs.watch.instances.knotd-reload.exec = [
          (lib.getExe' pkgs.systemd "systemctl")
          "reload-or-restart"
          "knot.service"
        ];
        services.knot.extraArgs = [
          "-v"
        ];
        services.knot.keyFiles = [
          # this will land at the beginning of file instead of `settings.include` somewhere in the middle
          "${cfg.knot.configDir}/*.conf"
        ];
        services.knot.settings = {
          server.listen = cfg.knot.listens;
          server.listen-tls = map (
            listener:
            {
              "${cfg.knot.localAddress}@${toString cfg.knot.localPort}" =
                "${cfg.knot.localAddress}@${toString cfg.knot.localPortTLS}";
            }
            ."${listener}" or listener
          ) cfg.knot.listens;
          server.listen-quic = map (
            listener:
            {
              "${cfg.knot.localAddress}@${toString cfg.knot.localPort}" =
                "${cfg.knot.localAddress}@${toString cfg.knot.localPortTLS}";
            }
            ."${listener}" or listener
          ) cfg.knot.listens;
          log = [
            {
              target = "syslog";
              any = "debug";
            }
          ];
          mod-dnstap = [
            {
              id = "debug";
              # read with `kdig -G /run/knot/dnstap.debug.tap +qr`
              sink = "/run/knot/dnstap.debug.tap";
              log-queries = "on";
              log-responses = "on";
              responses-with-queries = "on";
            }
          ];
          template = [
            {
              id = "default";
              global-module = [
                "mod-stats"
              ]
              ++ lib.optional cfg.debug.knot "mod-dnstap/debug";
              acl = [ "admin" ];
            }
            {
              id = "kea-updateable";
              acl = [
                "admin"
                "dhcp-ddns:${keaTSIGName}"
              ];
            }
          ];
          zone = lib.attrsets.mapAttrsToList (_: domainCfg: {
            domain = lib.strings.removeSuffix "." domainCfg.name;
            template = if builtins.elem domainCfg.name d2Domains then "kea-updateable" else "default";
            acl = [
              "admin"
            ]
            ++ lib.lists.optional (builtins.elem domainCfg.name d2Domains) "dhcp-ddns:${keaTSIGName}";
          }) cfg.domains;
          acl = [
            {
              id = "admin";
              key = "admin";
              action = [
                "query"
                "notify"
                "transfer"
                "update"
              ];
            }
            {
              id = "dhcp-ddns:${keaTSIGName}";
              key = keaTSIGName;
              action = [
                "query"
                "update"
              ];

              # queries done by `kea` https://github.com/search?q=repo%3Aisc-projects%2Fkea%20%22RRType%3A%3A%22&type=code
              update-type = [
                # A && AAAA https://github.com/isc-projects/kea/blob/3bc9a732f8288ba752e784ad10519d7e1635582f/src/bin/d2/simple_add.cc#L490
                "A"
                "AAAA"
                # DHCID https://github.com/isc-projects/kea/blob/3bc9a732f8288ba752e784ad10519d7e1635582f/src/bin/d2/simple_add.cc#L498-L499
                "DHCID"
                # PTR for reverse DNS https://github.com/isc-projects/kea/blob/3bc9a732f8288ba752e784ad10519d7e1635582f/src/bin/d2/simple_add.cc#L537-L540
                "PTR"
                #"SOA" # this is just a `SOA?` query https://github.com/isc-projects/kea/blob/3bc9a732f8288ba752e784ad10519d7e1635582f/src/lib/d2srv/d2_update_message.cc#L83
              ];

              # allow access to whatever zone the ACL is attached to
              update-owner = "zone";
              # allow access to sub-domain updates without the zone itself
              update-owner-match = "sub";
            }
          ];
        };
        environment.etc."${lib.strings.removePrefix "/etc" cfg.knot.configDir}/.keep".text = "";
        kdn.disks.persist."sys/data".directories = [
          {
            directory = cfg.knot.dataDir;
            user = "knot";
            group = "knot";
            mode = "0700";
          }
        ];
        kdn.networking.router.kresd.upstreams = [
          {
            description = "local knot-dns";
            type = "STUB";
            nameservers = [ "${cfg.knot.localAddress}@${toString cfg.knot.localPort}" ];
            domains = lib.pipe cfg.domains [
              builtins.attrValues
              (map (domainCfg: domainCfg.name))
            ];
          }
        ];
        kdn.networking.router.templates = lib.pipe cfg.tsig.keyTpls [
          (lib.attrsets.mapAttrsToList (
            id: keyCfg: {
              name = "knot/sops-key.${id}.conf";
              value = {
                path = "${cfg.knot.configDir}/sops-keys.${cfg.dropin.infix}.${id}.conf";
                owner = "knot";
                group = "knot";
                mode = "0400";
                content = ''
                  # ${keyCfg.algorithm}:${id}:${keyCfg.secret}
                  key:
                  - id: ${keyCfg.name}
                    algorithm: ${keyCfg.algorithm}
                    secret: ${keyCfg.secret}
                '';
              };
            }
          ))
          builtins.listToAttrs
        ];

        services.kea.dhcp-ddns.enable = true;
        kdn.networking.router = {
          kea.dhcp4.settings = {
            dhcp-ddns.enable-updates = true;
            # TODO: figure out why the DHCID changes, some day...
            ddns-conflict-resolution-mode = "check-exists-with-dhcid";
            ddns-generated-prefix = "ip";
            ddns-override-client-update = true;
            ddns-replace-client-name = "when-not-present";
            ddns-send-updates = false;
            ddns-update-on-renew = true;
          };
          kea.dhcp-ddns.settings = {
            dns-server-timeout = 500;
            # Both sets default to `{ }`, and both reads index them by one literal name. A tree
            # with no key then holds neither entry. `optional` drops the whole key instead, so
            # the setting carries no fake value.
            tsig-keys =
              lib.lists.optional (cfg.tsig.keyTpls ? "${keaTSIGName}" && cfg.tsig.keaSecrets ? "${keaTSIGName}")
                {
                  name = keaTSIGName;
                  algorithm = cfg.tsig.keyTpls.${keaTSIGName}.algorithm;
                  secret-file = cfg.tsig.keaSecrets.${keaTSIGName}.secret.path;
                };
            loggers = [
              {
                name = "kea-dhcp-ddns";
                severity = if cfg.debug.kea-dhcp-ddns then "DEBUG" else "INFO";
                debuglevel = 99;
                output_options = [ { output = "stderr"; } ];
              }
            ];
            forward-ddns.ddns-domains = lib.pipe d2Domains [
              (map (domain: {
                name = domain;
                key-name = keaTSIGName;
                dns-servers = [
                  {
                    ip-address = cfg.knot.localAddress;
                    port = cfg.knot.localPort;
                  }
                ];
              }))
            ];
            /*
              # TODO: reverse-ddns with generating arpa names (must be done after the values are rendered)
              #     eg: 2001:db8:1:: ->
              reverse-ddns.ddns-domains = lib.pipe cfg.nets [
                (lib.attrsets.mapAttrsToList (_: netCfg: netCfg.domain))
                lib.lists.unique
                (builtins.sort builtins.lessThan)

                (map (domain: {
                  name = domain;
                  key-name = keaTSIGName;
                  dns-servers = [
                    {
                      ip-address = cfg.knot.localAddress;
                      port = cfg.knot.localPort;
                    }
                  ];
                }))
              ];
            */
          };
        };
        kdn.networking.router.domains = lib.pipe d2Domains [
          (map (domain: {
            name = domain;
            value = { };
          }))
          builtins.listToAttrs
        ];
        systemd.services."kdn-knot-init" = {
          description = "Initialize knot's zonefiles";
          wantedBy = [ "knot.service" ];
          after = [ "knot.service" ];
          serviceConfig.Type = "oneshot";
          serviceConfig.RemainAfterExit = true;
          script =
            let
              zones = lib.pipe d2Domains [
                (map (
                  domain:
                  lib.strings.escapeShellArgs [
                    (lib.getExe kdn-router-knot-setup-zone)
                    "${cfg.knot.dataDir}/${domain}zone"
                    domain
                  ]
                ))
              ];
              hosts = lib.pipe cfg.nets [
                # TODO: flip those to be piped for easier reading
                (lib.attrsets.mapAttrsToList (
                  _: netCfg:
                  (lib.attrsets.mapAttrsToList (
                    _: addrCfg:
                    (lib.attrsets.mapAttrsToList
                      (
                        host: hostCfg:
                        lib.strings.escapeShellArgs [
                          (lib.getExe kdn-router-knot-ddns-update)
                          hostCfg.hostname
                          netCfg.domain
                          (if addrCfg.type == "ipv4" then "A" else "AAAA")
                          hostCfg.ip
                          "30"
                        ]
                      )
                      (
                        lib.attrsets.filterAttrs (
                          host: hostCfg: (hostCfg.ip != null) # && (config.services.kea.dhcp6.enable || addrCfg.type != "ipv6")
                        ) addrCfg.hosts
                      )
                    )
                  ) netCfg.addressing)
                ))
              ];
            in
            lib.pipe (zones ++ hosts) [
              lib.flatten
              # TODO: fix templated strings in here, maybe store those in templated JSON or something?
              (builtins.filter (entry: !(lib.strings.hasInfix "<SOPS:" entry)))
              (builtins.concatStringsSep "\n")
              (text: ''
                set -xeEuo pipefail
                ${text}
              '')
            ];
        };
      }
    )
  ];
}

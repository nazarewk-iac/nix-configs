# The NetBird clients of the old `networking` area, as a den aspect. It ports
# `modules/universal/networking/netbird/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs any number of NetBird clients side by side on one machine. Each client gets its own
# service, its own user and group, its own `nb-<name>` interface, its own local DNS resolver address
# and its own port. It renders four things per active client:
#
#   * a `services.netbird.clients.<name>` entry with the port, the resolver address and the
#     environment;
#   * a `40-kdn-netbird-nb-<name>` networkd file with two routing policy rules, for a client the
#     consumer marks with `systemd.enable`;
#   * a persistence entry for `/var/lib/<service>`;
#   * a group whose members are the client's users plus every admin.
#
# One `netbird.target` unit wants and follows every active client, so a single command stops them
# all.
#
# ## Class list: `nixos`, `darwin` and `homeManager`
#
# The old module puts `wireguard-tools` outside its context guard, so the tool reaches a Darwin host
# and a Home Manager user too. The `darwin` and `homeManager` targets carry that one package and
# nothing else. Every service effect stays in the `nixos` target, exactly as the old guard states.
#
# ## What the port changes
#
# 1. **`enable` goes, and the data is the switch.** The old module holds its whole body behind
#    `lib.mkIf (clients != { })`, and that gate stays: a consumer that names no client gets no
#    service and no unit. So inclusion alone is inert, and no `enable` option is needed.
# 2. **`default.enable` becomes `default.active`.** `kdn.networking.netbird.default.enable` is a
#    reachable `enable` option, and this tree forbids one. The name changes; the meaning does not.
#    The per-client `enable` flag stays, because it sits inside an `attrsOf submodule`.
# 3. **`useOwnPackages` becomes five package options — the no-overlay part.** The old module reads
#    `pkgs.kdn.netbird` and four siblings, and that needs this repository's package overlay. An
#    adopter has no such overlay. This aspect declares `kdn.networking.netbird.packages.*` instead,
#    each `null` by default, and a non-null value becomes a `lib.mkDefault` on the matching nixpkgs
#    option. A consumer that wants this repository's own build names it.
# 4. **The sops read becomes two plain options — the de-personalized part.** The old module reads one
#    hardcoded secrets path, `default/netbird/<key>`. That layout belongs to one person's secrets
#    tree. This aspect declares `kdn.networking.netbird.secretsTree`, and each client's `secrets`
#    default reads `secretsTree.<secretKey>`. The shape a client expects is unchanged: an optional
#    `env` entry with a `path`, and an optional `<type>.setup-key` entry with a `path`.
# 5. **The secrets gate becomes the data itself.** The old module wraps the secret half in
#    `lib.mkIf config.kdn.security.secrets.allowed`, an option of another area. A client with no
#    secrets answers `null`, and the inner conditions already test that. So the port drops the outer
#    gate and keeps the inner ones, and a consumer that supplies no secret gets no secret wiring.
# 6. **The persistence write goes through the shared declaration.** ../common/persist.nix declares
#    `kdn.disks.persist`, and the `nixos` target imports it by path.
# 7. **The package list becomes the native option per class.** Each target writes
#    `environment.systemPackages`, `environment.systemPackages` or `home.packages` through
#    ../common/filter-packages.nix.
# 8. **The port default tolerates a class with no NetBird service.** The old default reads
#    `config.services.netbird.package.version`, and only the NixOS class declares that option. The
#    read gets an `or null` fallback, and a null answers port 0 — the value that asks NetBird to pick
#    a free port itself.
#
# TODO: switch to `network-online.target` instead of `network.target`, so a client initializes
# correctly.
#
# TODO: add an instance-switcher script. It confirms which instance runs, stops every instance,
# starts the selected one, and proxies the `netbird` command at the active instance.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 2.
# 3. **No custom module argument.** Each target module takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  packages = pkgs: with pkgs; [ wireguard-tools ];

  filtered = lib: pkgs: import ../common/filter-packages.nix { inherit lib; } (packages pkgs);

  declaration =
    { config, lib, ... }:
    let
      cfg = config.kdn.networking.netbird;
    in
    {
      options.kdn.networking.netbird.admins = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        example = [ "root" ];
        description = "The user names that join the group of every client.";
      };

      options.kdn.networking.netbird.packages.client = lib.mkOption {
        type = with lib.types; nullOr package;
        default = null;
        description = ''
          The NetBird client build. `null` keeps the nixpkgs default.

          A non-null value becomes `lib.mkDefault` on `services.netbird.package`, so a consumer's own
          plain assignment still wins.
        '';
      };
      options.kdn.networking.netbird.packages.ui = lib.mkOption {
        type = with lib.types; nullOr package;
        default = null;
        description = "The NetBird graphical client build. `null` keeps the nixpkgs default.";
      };
      options.kdn.networking.netbird.packages.signal = lib.mkOption {
        type = with lib.types; nullOr package;
        default = null;
        description = "The NetBird signal server build. `null` keeps the nixpkgs default.";
      };
      options.kdn.networking.netbird.packages.management = lib.mkOption {
        type = with lib.types; nullOr package;
        default = null;
        description = "The NetBird management server build. `null` keeps the nixpkgs default.";
      };
      options.kdn.networking.netbird.packages.dashboard = lib.mkOption {
        type = with lib.types; nullOr package;
        default = null;
        description = "The NetBird dashboard build. `null` keeps the nixpkgs default.";
      };

      options.kdn.networking.netbird.secretsTree = lib.mkOption {
        type = with lib.types; nullOr (attrsOf raw);
        default = null;
        example = lib.literalExpression ''
          {
            work.env.path = "/run/secrets/netbird-work-env";
            work.permanent.setup-key.path = "/run/secrets/netbird-work-setup-key";
          }
        '';
        description = ''
          The secrets of every client, keyed by the client's own `secretKey`. Each entry may hold an
          `env` attribute with a `path`, and a `<type>.setup-key` attribute with a `path`.

          This aspect names no secrets manager and no secrets layout. A consumer passes the subtree
          its own manager produces. `null` means the machine holds no NetBird secret.
        '';
      };

      options.kdn.networking.netbird.default.users = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description = "The user names every client takes when the client names none itself.";
      };
      options.kdn.networking.netbird.default.environment = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = { };
        description = ''
          The environment every client takes. Each key lands at priority 1100, so a client's own
          `environment` key wins and a consumer's plain assignment wins over both.
        '';
      };
      options.kdn.networking.netbird.default.active = lib.mkOption {
        type = with lib.types; bool;
        default = true;
        example = false;
        description = ''
          Run a client that states nothing itself. It is the default of each client's own `enable`
          flag.

          The old option name is `default.enable`. This tree forbids a reachable `enable` option, so
          the name changed and the meaning did not.
        '';
      };

      options.kdn.networking.netbird.clients = lib.mkOption {
        default = { };
        description = "One entry per NetBird client this machine runs.";
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }@nbArgs:
            let
              nbCfg = nbArgs.config;
            in
            {
              options.enable = lib.mkOption {
                type = with lib.types; bool;
                default = cfg.default.active;
                defaultText = lib.literalExpression "config.kdn.networking.netbird.default.active";
                description = "Run this client.";
              };
              options.name = lib.mkOption {
                type = with lib.types; str;
                default = name;
                description = "The NetBird client name.";
              };
              options.serviceName = lib.mkOption {
                type = with lib.types; str;
                default = "netbird-${name}";
                description = "The systemd service name of this client.";
              };
              options.userName = lib.mkOption {
                type = with lib.types; str;
                default = nbCfg.serviceName;
                description = "The user that owns this client's state directory.";
              };
              options.groupName = lib.mkOption {
                type = with lib.types; str;
                default = nbCfg.serviceName;
                description = "The group that reaches this client's socket.";
              };
              options.interface = lib.mkOption {
                readOnly = true;
                default = "nb-${name}";
                description = "The WireGuard interface name of this client. It is read-only.";
              };

              options.secretKey = lib.mkOption {
                type = with lib.types; str;
                default = nbCfg.name;
                description = "The key of this client's entry inside `secretsTree`.";
              };
              options.secrets = lib.mkOption {
                description = ''
                  This client's own secrets subtree, or `null` when the consumer supplies none.

                  It defaults to `secretsTree.<secretKey>`, so a consumer points `secretsTree` at its
                  own layout once and every client finds its entry.
                '';
                default =
                  let
                    tree = if cfg.secretsTree == null then { } else cfg.secretsTree;
                  in
                  if tree ? "${nbCfg.secretKey}" then tree."${nbCfg.secretKey}" else null;
                defaultText = lib.literalExpression "config.kdn.networking.netbird.secretsTree.<secretKey>";
              };

              options.idx = lib.mkOption {
                type = with lib.types; ints.between 0 20;
                example = 0;
                description = ''
                  The index of this client on this machine. It picks the port and the local resolver
                  address, so two clients of one machine need two different values.
                '';
              };

              options.port = lib.mkOption {
                type = with lib.types; port;
                # 0 asks NetBird 0.50.2 and later to pick a free port itself.
                default =
                  let
                    version = config.services.netbird.package.version or null;
                  in
                  if
                    version != null && lib.strings.hasPrefix "0." version && lib.strings.versionOlder version "0.50.2"
                  then
                    51820 - nbCfg.idx
                  else
                    0;
                defaultText = lib.literalExpression "0, or `51820 - idx` before NetBird 0.50.2";
                description = "The WireGuard port of this client.";
              };

              options.localAddress = lib.mkOption {
                type = with lib.types; str;
                default = "127.5.18.${toString (20 - nbCfg.idx)}";
                defaultText = lib.literalExpression ''"127.5.18.''${20 - idx}"'';
                description = ''
                  The loopback address this client serves DNS on. Each index gets its own address, so
                  two clients never share a listener.
                '';
              };

              options.type = lib.mkOption {
                type =
                  with lib.types;
                  enum [
                    "ephemeral"
                    "permanent"
                  ];
                default = "permanent";
                description = "The setup-key kind this client uses. It names the `secrets` sub-entry.";
              };

              options.users = lib.mkOption {
                type = with lib.types; listOf str;
                default = cfg.default.users;
                defaultText = lib.literalExpression "config.kdn.networking.netbird.default.users";
                description = "The users that reach this client. The `apply` adds every admin and sorts the result.";
                apply =
                  users:
                  lib.pipe users [
                    (u: u ++ cfg.admins)
                    (builtins.sort builtins.lessThan)
                    lib.lists.uniqueStrings
                  ];
              };
              options.environment = lib.mkOption {
                type = with lib.types; attrsOf str;
                default = { };
                description = "The environment of this client's service. Each key lands as `lib.mkDefault`.";
              };

              options.systemd.enable = lib.mkOption {
                type = with lib.types; bool;
                default = false;
                example = true;
                description = "Render a networkd file for this client's interface, with the two routing policy rules.";
              };

              options.resolvesDomains = lib.mkOption {
                type = with lib.types; nullOr (listOf str);
                default = null;
                description = "The search domains this client's resolver answers. `null` names none.";
              };
            }
          )
        );
      };
    };

  nixosTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.networking.netbird;
      activeCfgs = lib.pipe cfg.clients [
        builtins.attrValues
        (builtins.filter (nbCfg: nbCfg.enable))
      ];
    in
    {
      imports = [
        declaration
        ../common/persist.nix
      ];

      config = lib.mkMerge [
        # The command list follows the inclusion, exactly as the old `enable` gate did. Every service
        # effect below follows the client data instead.
        {
          environment.systemPackages = filtered lib pkgs;
        }
        (lib.mkIf (cfg.clients != { }) (
          lib.mkMerge [
            {
              # 2026-03-23: the graphical client failed to build.
              services.netbird.ui.enable = false;
            }
            {
              services.netbird.package = lib.mkIf (cfg.packages.client != null) (
                lib.mkDefault cfg.packages.client
              );
              services.netbird.ui.package = lib.mkIf (cfg.packages.ui != null) (lib.mkDefault cfg.packages.ui);
              services.netbird.server.signal.package = lib.mkIf (cfg.packages.signal != null) (
                lib.mkDefault cfg.packages.signal
              );
              services.netbird.server.management.package = lib.mkIf (cfg.packages.management != null) (
                lib.mkDefault cfg.packages.management
              );
              services.netbird.server.dashboard.package = lib.mkIf (cfg.packages.dashboard != null) (
                lib.mkDefault cfg.packages.dashboard
              );
            }
            {
              systemd.targets.netbird =
                let
                  services = map (nbCfg: "${nbCfg.serviceName}.service") activeCfgs;
                in
                {
                  wants = services;
                  after = services;
                  unitConfig.PropagatesStopTo = services;
                };
            }
            {
              services.netbird.clients = lib.pipe activeCfgs [
                (map (nbCfg: {
                  "${nbCfg.name}" = {
                    port = nbCfg.port;
                    dns-resolver.address = nbCfg.localAddress;
                    environment =
                      builtins.mapAttrs (_: lib.mkOverride 1100) cfg.default.environment
                      // builtins.mapAttrs (_: lib.mkDefault) nbCfg.environment;
                  };
                }))
                lib.mkMerge
              ];

              systemd.network.networks = lib.pipe activeCfgs [
                (builtins.filter (nbCfg: nbCfg.systemd.enable))
                (map (nbCfg: {
                  name = "40-kdn-netbird-${nbCfg.interface}";
                  value = {
                    matchConfig.Name = nbCfg.interface;
                    linkConfig = {
                      ActivationPolicy = "manual";
                    };
                    dns = [ nbCfg.localAddress ];
                    domains = lib.mkIf (nbCfg.resolvesDomains != null) nbCfg.resolvesDomains;
                    routingPolicyRules = [
                      {
                        # 105:    from all lookup main suppress_prefixlength 0
                        Priority = 105;
                        Table = "main";
                        SuppressPrefixLength = 0;
                      }
                      {
                        # 110:    not from all fwmark 0x1bd00 lookup 7120
                        Priority = 110;
                        # not from all
                        InvertRule = true;
                        # fwmark 0x1bd00
                        FirewallMark = 113920;
                        # lookup 7120
                        Table = 7120;
                      }
                    ];
                  };
                }))
                builtins.listToAttrs
              ];

              kdn.disks.persist."usr/data".directories = lib.pipe activeCfgs [
                (map (nbCfg: {
                  directory = "/var/lib/${nbCfg.serviceName}";
                  user = nbCfg.userName;
                  group = nbCfg.groupName;
                  mode = "0700";
                }))
              ];

              users.groups = lib.pipe activeCfgs [
                (map (nbCfg: lib.attrsets.nameValuePair nbCfg.groupName { members = nbCfg.users; }))
                builtins.listToAttrs
              ];
            }
            {
              services.netbird.clients = lib.pipe activeCfgs [
                (map (nbCfg: {
                  name = nbCfg.name;
                  value = lib.mkIf (nbCfg.secrets != null && nbCfg.secrets ? "${nbCfg.type}".setup-key) {
                    login.enable = true;
                    login.systemdDependencies = [ "kdn-secrets.target" ];
                    login.setupKeyFile = nbCfg.secrets."${nbCfg.type}".setup-key.path;
                  };
                }))
                builtins.listToAttrs
              ];
              systemd.services = lib.pipe activeCfgs [
                (map (nbCfg: {
                  name = nbCfg.serviceName;
                  value = lib.mkIf (nbCfg.secrets != null && nbCfg.secrets ? env) {
                    after = [ "kdn-secrets.target" ];
                    requires = [ "kdn-secrets.target" ];
                    serviceConfig.LoadCredential = [ "env:${nbCfg.secrets.env.path}" ];
                    serviceConfig.EnvironmentFile = "-%d/env";
                  };
                }))
                builtins.listToAttrs
              ];
            }
          ]
        ))
      ];
    };

  darwinTarget =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];
      config.environment.systemPackages = filtered lib pkgs;
    };

  homeTarget =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];
      config.home.packages = filtered lib pkgs;
    };
in
{
  kdn.net-netbird.nixos = nixosTarget;
  kdn.net-netbird.darwin = darwinTarget;
  kdn.net-netbird.homeManager = homeTarget;
}

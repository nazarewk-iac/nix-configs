# The Zammad helpdesk, as a den aspect. It ports
# `modules/universal/services/zammad/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs Zammad with a local PostgreSQL database and a local Redis server. It grants the web unit
# the one capability it needs to bind a privileged port.
#
# ## It includes the database aspect
#
# The old module writes `kdn.services.postgresql.enable`. An aspect must not write another aspect's
# option, so this aspect **includes** `service-postgresql` instead. den collapses the diamond when
# the consumer includes both.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The aspect names no address.** The old module states a loopback address for the web service
#    and another for Redis. Both nixpkgs modules carry a sane default, so this aspect passes an
#    address only when the consumer names one.
# 3. **The Redis port becomes an option with no default.** The old module states one arbitrary port.
#    `null` keeps the nixpkgs default.
# 4. **The capability follows the port.** The aspect grants `CAP_NET_BIND_SERVICE` only for a
#    privileged port.
# 5. **The persist write becomes an output option.** See below.
#
# ## The persist directories become a read-only output
#
#     kdn.disks.persist."sys/data".directories = config.kdn.services.zammad.persist.sysData;
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config` and `lib` only.
{ kdn, ... }:
{
  kdn.service-zammad.includes = [ kdn.service-postgresql ];

  kdn.service-zammad.nixos =
    { config, lib, ... }:
    let
      cfg = config.kdn.services.zammad;
      uCfg = config.services.zammad;
    in
    {
      options.kdn.services.zammad.host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The address the web service binds. `null` keeps the nixpkgs default, which is the
          loopback interface.
        '';
      };

      options.kdn.services.zammad.port = lib.mkOption {
        type = lib.types.port;
        default = 80;
        description = ''
          The port the web service binds. 80 is the standard HTTP port. A port below 1024 also
          grants the web unit `CAP_NET_BIND_SERVICE`.
        '';
      };

      options.kdn.services.zammad.user = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "zammad";
        description = "The system user the nixpkgs module runs the service as.";
      };

      options.kdn.services.zammad.group = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "zammad";
        description = "The system group the nixpkgs module runs the service as.";
      };

      options.kdn.services.zammad.redis.fullName = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "redis-${uCfg.redis.name}";
        defaultText = lib.literalExpression ''"redis-" + config.services.zammad.redis.name'';
        description = "The state directory name of the local Redis server.";
      };

      options.kdn.services.zammad.redis.address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The address the local Redis server binds. `null` keeps the nixpkgs default, which is the
          loopback interface.
        '';
      };

      options.kdn.services.zammad.redis.port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "The port the local Redis server binds. `null` keeps the nixpkgs default.";
      };

      options.kdn.services.zammad.persist.sysData = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
        readOnly = true;
        description = ''
          The directories this aspect wants on persistent system storage. The consumer wires the
          list into its own persistence option.
        '';
      };

      config = lib.mkMerge [
        {
          services.zammad.enable = true;
          services.zammad.port = cfg.port;
          services.zammad.database.createLocally = true;
          services.zammad.redis.createLocally = true;
          # One dynamic key per attribute set: two dynamic keys with the same name in one set is an
          # error.
          services.redis.servers."${uCfg.redis.name}" = {
            user = cfg.user;
            group = cfg.group;
          };

          kdn.services.zammad.persist.sysData = [
            {
              directory = "/var/lib/${cfg.redis.fullName}";
              user = cfg.user;
              group = cfg.group;
              mode = "0750";
            }
            {
              directory = uCfg.dataDir;
              user = cfg.user;
              group = cfg.group;
              mode = "0750";
            }
          ];
        }
        (lib.mkIf (cfg.host != null) {
          services.zammad.host = cfg.host;
        })
        (lib.mkIf (cfg.redis.port != null) {
          services.zammad.redis.port = cfg.redis.port;
        })
        (lib.mkIf (cfg.redis.address != null) {
          services.redis.servers."${uCfg.redis.name}".bind = cfg.redis.address;
        })
        (lib.mkIf (cfg.port < 1024) {
          systemd.services.zammad-web.serviceConfig.AmbientCapabilities = [
            "CAP_NET_BIND_SERVICE"
          ];
        })
      ];
    };
}

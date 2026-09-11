# The PostgreSQL server, as a den aspect. It ports
# `modules/universal/services/postgresql/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs PostgreSQL on a NixOS host, and it publishes the data directory that a persistent host
# must keep.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The persist write becomes an output option.** See below.
#
# ## The persist directories become a read-only output
#
# The old module writes `kdn.disks.persist."sys/data".directories`. An aspect must not write another
# aspect's option, so this aspect publishes the list and the consumer wires it in one line:
#
#     kdn.disks.persist."sys/data".directories =
#       config.kdn.services.postgresql.persist.sysData;
#
# The list holds one attribute set, in the shape the persistence module takes: `directory`, `user`,
# `group` and `mode`.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config` and `lib` only.
{ ... }:
{
  kdn.service-postgresql.nixos =
    { config, lib, ... }:
    let
      cfg = config.kdn.services.postgresql;
    in
    {
      options.kdn.services.postgresql.user = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "postgres";
        description = "The system user the nixpkgs module runs the server as.";
      };

      options.kdn.services.postgresql.group = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "postgres";
        description = "The system group the nixpkgs module runs the server as.";
      };

      options.kdn.services.postgresql.persist.sysData = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
        readOnly = true;
        description = ''
          The directories this aspect wants on persistent system storage. The consumer wires the
          list into its own persistence option.
        '';
      };

      config.services.postgresql.enable = true;

      config.kdn.services.postgresql.persist.sysData = [
        {
          directory = config.services.postgresql.dataDir;
          user = cfg.user;
          group = cfg.group;
          mode = "0750";
        }
      ];
    };
}

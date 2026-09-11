# Syncthing file synchronization, as a den aspect. It ports
# `modules/universal/services/syncthing/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs Syncthing as a user service, with the configuration under `XDG_CONFIG_HOME` and the data
# under `XDG_DATA_HOME`. It turns the tray icon off.
#
# ## The web interface keeps the Syncthing default
#
# The old module passes `--gui-address` with a literal value. Syncthing already binds the loopback
# interface by itself, so this aspect passes the flag only when the consumer names an address in
# `guiAddress`. So the aspect states no address of its own.
#
# ## One class only
#
# The old module runs the service in the Home Manager context, and only when the parent is NixOS.
# So this aspect serves the `homeManager` class only, and the whole target sits behind an
# `isLinux` test: Syncthing needs a systemd user service, and a darwin home has none.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The Home Manager forward goes.** A den consumer includes the aspect where it wants it.
# 3. **`kdn.env.packages` does not survive.** The target writes `home.packages`. Design B. The old
#    module installs `stc-cli` in both contexts; the home context keeps it here.
# 4. **The persist writes become output options.** See below.
#
# ## The persist directories become read-only outputs
#
# The old module writes two `kdn.disks.persist.*` buckets. An aspect must not write another aspect's
# option, so this aspect publishes two lists and the consumer wires them:
#
#     kdn.disks.persist."usr/data".directories = config.kdn.services.syncthing.persist.usrData;
#     kdn.disks.persist."usr/config".directories = config.kdn.services.syncthing.persist.usrConfig;
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.service-syncthing.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.services.syncthing;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      options.kdn.services.syncthing.guiAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The address the web interface binds, as `<host>:<port>`. `null` keeps the Syncthing
          default, which is the loopback interface.
        '';
      };

      options.kdn.services.syncthing.persist.usrData = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The data directories this aspect wants on persistent storage, relative to the home
          directory. The consumer wires the list into its own persistence option.
        '';
      };

      options.kdn.services.syncthing.persist.usrConfig = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The configuration directories this aspect wants on persistent storage, relative to the
          home directory. The consumer wires the list into its own persistence option.
        '';
      };

      config = lib.mkMerge [
        {
          kdn.services.syncthing.persist.usrData = [
            ".local/share/syncthing"
          ];
          kdn.services.syncthing.persist.usrConfig = [
            ".config/syncthing"
          ];
        }
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          home.packages = filterPackages [ pkgs.stc-cli ];

          services.syncthing.enable = true;
          services.syncthing.extraOptions = [
            # see https://docs.syncthing.net/users/syncthing.html
            "--config=${config.xdg.configHome}/syncthing"
            "--data=${config.xdg.dataHome}/syncthing"
            "--auditfile=--"
          ]
          ++ lib.optional (cfg.guiAddress != null) "--gui-address=${cfg.guiAddress}";
          services.syncthing.tray.enable = false;

          systemd.user.services.syncthing.Unit.After = [ "paths.target" ];
        })
      ];
    };
}

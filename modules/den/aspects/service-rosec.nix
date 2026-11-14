# `rosec` — a Secret Service daemon whose store is a sops-encrypted file tree, as a den aspect.
# It ports `modules/universal/services/rosec/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs `rosecd` as a **user** unit that owns `org.freedesktop.secrets`, renders
# `~/.config/rosec/config.toml` from the option tree, and puts `sops` and the age plugin on the
# unit `PATH`. A second switch adds a conflict report: a path unit, a polling timer and one
# notification per new sops-store conflict.
#
# ## One class only
#
# The old module forwards its whole tree from a NixOS host into Home Manager. A den consumer
# includes the aspect where it wants it, so this aspect emits `homeManager` alone: a user unit, a
# file under `XDG_CONFIG_HOME`, and a `home.packages` entry all live there. A NixOS half would add
# nothing the unit does not already get.
#
# ## The `enable` split, and why it differs from the usual port
#
# An aspect holds no `enable` option — inclusion is the switch. This aspect keeps **two** switches
# anyway, and both are data:
#
# 1. `kdn.services.rosec.use` — run the daemon.
# 2. `kdn.services.rosec.conflictNotification.use` — run the conflict report.
#
# The reason is the same one the old module states: KeePassXC already claims
# `org.freedesktop.secrets` on this host, and two units cannot hold one bus name. A consumer that
# includes this aspect to get the conflict report must not silently kill its password manager. So
# inclusion brings the **option tree and the CLI**, and the two switches gate the units. A consumer
# that wants the daemon writes one of the two lines below:
#
#     kdn.services.rosec.use = true;
#     kdn.services.rosec.conflictNotification.use = true;
#
# The name is `use`, not `enable`, because the aspect rules forbid a reachable `enable`.
#
# ## The package comes from the flake input
#
# The daemon and the CLI must be one build, or the config the module writes may not match the
# options the binary reads. So the default package is `inputs.rosec.packages.<system>.rosec`, and
# the aspect reads `inputs` from its own scope — a target module takes `config`, `lib` and `pkgs`
# only. See ./security-secrets-sops.nix for the same shape.
#
# ## The conflict report
#
# The provider archives a losing value as `.superseded-<id>.<nanos>-<host>.sops.yaml` and, later in
# the fork, writes a `.conflicts/*.md` marker. Both are silent. `rosec-conflicts` lists them,
# notifies once per new conflict, and records it in `~/.local/state/rosec/conflicts.json`. A systemd
# path unit is the fast route and a timer is the backstop (`inotify` misses a rename a sync client
# makes). The script dedupes, so the two routes cannot notify twice.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. `use` is the gated name.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ kdn, inputs, ... }:
let
  # The script is one file, shared with the old tree. A relative path literal makes a store object of
  # this file alone, not of the whole repository.
  scriptSource = ../../universal/services/rosec/rosec-conflicts.sh;
in
{
  kdn.service-rosec.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.services.rosec;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      configFormat = pkgs.formats.toml { };

      providerOptions = {
        key_file = cfg.providers.sops.key_file;
        sops_binary = cfg.providers.sops.sops_binary;
        probe_timeout_seconds = cfg.providers.sops.probe_timeout_seconds;
      }
      // lib.optionalAttrs (cfg.providers.sops.age_recipient != null) {
        age_recipient = cfg.providers.sops.age_recipient;
      }
      // lib.optionalAttrs (cfg.providers.sops.identity_file != "") {
        identity_file = cfg.providers.sops.identity_file;
      }
      // lib.optionalAttrs (cfg.providers.sops.identity_key_file != "") {
        identity_key_file = cfg.providers.sops.identity_key_file;
      }
      // lib.optionalAttrs (cfg.providers.sops.runtime_identity_file != "") {
        runtime_identity_file = cfg.providers.sops.runtime_identity_file;
      };

      rosecConfig = {
        service = {
          inherit (cfg) ssh_fuse;
        };
        provider = [
          {
            inherit (cfg.providers.sops) id;
            kind = "sops";
            inherit (cfg.providers.sops) path;
            options = providerOptions;
          }
        ];
      };

      rosecConfigFile = configFormat.generate "rosec-config.toml" rosecConfig;

      # `rosecd` shells out to `sops`, and `sops` resolves the age plugin from the same `PATH`.
      servicePath = lib.makeBinPath (
        [
          cfg.package
          cfg.providers.sops.sopsPackage
          cfg.providers.sops.agePluginYubikeyPackage
        ]
        ++ cfg.extraPackages
      );

      conflictsScript = pkgs.writeShellApplication {
        name = "rosec-conflicts";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnused
          pkgs.python3
        ]
        ++ lib.optional cfg.conflictNotification.notify pkgs.libnotify
        ++ lib.optional cfg.conflictNotification.swaync pkgs.swaynotificationcenter;
        text = builtins.readFile scriptSource;
      };

      notificationPath = lib.makeBinPath (
        [ conflictsScript ]
        ++ lib.optional cfg.conflictNotification.notify pkgs.libnotify
        ++ lib.optional cfg.conflictNotification.swaync pkgs.swaynotificationcenter
      );

      # A systemd path unit takes an absolute path or a unit specifier, not a `~/` prefix. `%h` is
      # the home directory, so the option keeps the `~/` form the provider itself expands.
      systemdUnitPath =
        path: if lib.hasPrefix "~/" path then "%h/${lib.removePrefix "~/" path}" else path;
    in
    {
      options.kdn.services.rosec = {
        use = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Run `rosecd` as a user unit.

            The old module names this option `enable`. An aspect holds no reachable `enable`, so the
            name changed and the behaviour did not.

            Keep it `false` on a host whose password manager already claims
            `org.freedesktop.secrets`: two units cannot hold that bus name, and the loser is killed.
          '';
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.rosec.packages.${pkgs.stdenv.hostPlatform.system}.rosec;
          defaultText = lib.literalExpression "inputs.rosec.packages.\${system}.rosec";
          description = ''
            The rosec package. The default is the fork's own flake output, so the daemon and the CLI
            cannot drift apart.
          '';
        };

        extraPackages = lib.mkOption {
          type = with lib.types; listOf package;
          default = [ ];
          description = "Extra packages on the unit `PATH`, for a provider that shells out further.";
        };

        providers.sops.id = lib.mkOption {
          type = lib.types.str;
          default = "sops";
          description = "The provider id. It names the provider in `rosec provider <id> unlock`.";
        };

        providers.sops.path = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "~/Nextcloud/drag0nius@nc.nazarewk.pw/important/rosec-storage";
          description = ''
            The store root: one directory per collection, one `<id>.sops.yaml` per item. A `~/`
            prefix is accepted and expanded by the provider.

            This is a `str`, not a `path`: the store lives in a synced directory under the home
            directory, and copying it into the Nix store would be wrong.
          '';
        };

        providers.sops.key_file = lib.mkOption {
          type = lib.types.str;
          default = "~/.config/sops/age/keys.txt";
          description = ''
            The age identity file. The provider exports it as `SOPS_AGE_KEY_FILE`. In `derived`
            mode it is used only to unwrap the master identity, once per session.
          '';
        };

        providers.sops.identity_file = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            The sops-encrypted master identity of a `derived`-mode store (for example
            `~/…/rosec-storage/.rosec-store-identity.sops.yaml`). Empty means `direct` mode.

            The mode is recorded in `<store>/.rosec-store.yaml` and is fixed at creation; the
            provider refuses a mismatch. Change modes only by migrating to a new store.
          '';
        };

        providers.sops.identity_key_file = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            The key used only to unwrap `identity_file`. Empty reuses `key_file`. A PGP/KMS master
            rule ignores this age key file.
          '';
        };

        providers.sops.runtime_identity_file = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            Where the unwrapped master is written while unlocked. Empty uses
            `$XDG_RUNTIME_DIR/rosec/store-identity.age` (mode 0600); `lock` removes it.
          '';
        };

        providers.sops.age_recipient = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          description = ''
            The recipient for new and changed files. `direct` mode: the unlock key recipient.
            `derived` mode: the derived public key printed by `rosec-sops identity init`.
            Comma-separated lists are allowed; `null` lets the store `.sops.yaml` decide.
          '';
        };

        providers.sops.sops_binary = lib.mkOption {
          type = lib.types.str;
          default = "sops";
          description = "The `sops` executable name as the provider calls it.";
        };

        providers.sops.sopsPackage = lib.mkOption {
          type = lib.types.package;
          default = pkgs.sops;
          description = "The `sops` package placed on the unit `PATH`.";
        };

        providers.sops.agePluginYubikeyPackage = lib.mkOption {
          type = lib.types.package;
          default = pkgs.age-plugin-yubikey;
          description = "The age plugin package placed on the unit `PATH`.";
        };

        providers.sops.probe_timeout_seconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 30;
          description = "The ceiling for the decrypt that `unlock` runs to prove the identity works.";
        };

        ssh_fuse = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Mount the SSH-agent FUSE filesystem. `false` is the default: the provider-independent
            switch is off, and a dedicated agent already serves the socket.
          '';
        };

        conflictNotification.use = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Run the conflict report: one notification and one persistent state record per new
            sops-store conflict.

            It reads the store, not the daemon, so it may run while `use` is still `false`.
          '';
        };

        conflictNotification.notify = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Send the notification with `notify-send`.";
        };

        conflictNotification.swaync = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Poke the swaync control centre (`swaync-client -t`) after a notification.";
        };

        conflictNotification.interval = lib.mkOption {
          type = lib.types.str;
          default = "1min";
          description = ''
            How often the polling timer rescans the store. The timer is the **reliable** route: a
            systemd path unit watches one directory and is not recursive, so a write inside a
            collection directory does not trigger it. The scan reads file names only, so one minute
            is cheap even on a synced store.
          '';
        };

        conflictNotification.stateFile = lib.mkOption {
          type = lib.types.str;
          default = "~/.local/state/rosec/conflicts.json";
          description = "The persistent conflict record. One entry per conflict, keyed by path.";
        };
      };

      config = lib.mkMerge [
        {
          assertions = [
            {
              assertion = !cfg.use || cfg.providers.sops.path != "";
              message = "kdn.services.rosec.providers.sops.path must name the store root when `use` is true";
            }
          ];

          # The CLI and the conflict command reach the profile, so a terminal can unlock the provider
          # and list the conflicts without the daemon.
          home.packages = filterPackages [
            cfg.package
            conflictsScript
          ];
        }

        # The provider config is also the CLI's config: `rosec-sops conflicts list|show|resolve`
        # reads `~/.config/rosec/config.toml` when `--store` is absent. Render it whenever this
        # aspect is active, not only when the daemon runs, or the CLI fails on a host that still
        # keeps its password manager on the bus.
        (lib.mkIf (cfg.use || cfg.conflictNotification.use) {
          xdg.configFile."rosec/config.toml".source = rosecConfigFile;
        })

        (lib.mkIf cfg.use {
          systemd.user.services.rosecd = {
            Unit = {
              Description = "rosec Secret Service daemon (sops file tree)";
              Documentation = [ "https://github.com/jmylchreest/rosec" ];
              # Headless: the daemon serves CLI clients over SSH and in a TTY too, so it follows the
              # user manager and not `graphical-session.target`.
              PartOf = [ "default.target" ];
              After = [ "default.target" ];
            };

            Service = {
              Type = "dbus";
              BusName = "org.freedesktop.secrets";
              ExecStart = lib.getExe' cfg.package "rosecd";
              Environment = [
                "PATH=${servicePath}"
                "SOPS_AGE_KEY_FILE=${cfg.providers.sops.key_file}"
              ];
              Restart = "on-failure";
              RestartSec = 2;
              # A cold start waits for the YubiKey. Wide enough for a slow token, still bounded when
              # the token is absent.
              TimeoutStartSec = "60s";
            };

            Install.WantedBy = [ "default.target" ];
          };
        })

        (lib.mkIf cfg.conflictNotification.use {
          # The state directory exists before the first run.
          home.file.".local/state/rosec/.keep".text = "";

          systemd.user.services.rosec-conflicts = {
            Unit.Description = "report rosec sops-store conflicts";

            Service = {
              Type = "oneshot";
              ExecStart = lib.escapeShellArgs [
                (lib.getExe conflictsScript)
                "--store"
                cfg.providers.sops.path
                "--state"
                cfg.conflictNotification.stateFile
              ];
              Environment = [ "PATH=${notificationPath}" ];
              # A synced directory may be offline. The timer retries, so a missing store is not a
              # failed unit.
              SuccessExitStatus = [
                0
                2
              ];
            };
          };

          systemd.user.paths.rosec-conflicts = {
            Unit.Description = "watch the rosec sops store for conflict archives";
            Path = {
              # `PathModified` covers `PathChanged` (it also fires on a simple write), so one
              # directive is enough. A path unit is **not recursive**: a write inside a collection
              # directory changes that directory, not the store root, so the timer is the reliable
              # route. This unit still catches a new collection or a root-level file.
              #
              # `DirectoryNotEmpty` is level-triggered: a store that holds any item is never empty,
              # so the unit re-fires after every scan until it hits the trigger limit and fails.
              PathModified = [ (systemdUnitPath cfg.providers.sops.path) ];
              # A burst of renames from the sync client must not queue a hundred scans. The bound
              # is wide enough for a normal sync and still stops a runaway loop.
              TriggerLimitBurst = 30;
              TriggerLimitIntervalSec = "60s";
            };
            Install.WantedBy = [ "default.target" ];
          };

          systemd.user.timers.rosec-conflicts = {
            Unit.Description = "periodic rosec sops-store conflict scan";
            Timer = {
              # A conflict present at login is reported within a minute.
              OnStartupSec = "1min";
              OnUnitActiveSec = cfg.conflictNotification.interval;
              Unit = "rosec-conflicts.service";
            };
            Install.WantedBy = [ "timers.target" ];
          };
        })
      ];
    };
}

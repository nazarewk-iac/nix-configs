# `rosec` — a Secret Service daemon whose store is a sops-encrypted file tree.
#
# The package is the `nazarewk-iac/rosec` fork from `kdnConfig.inputs.rosec`. It carries the native
# `rosec-sops` provider: one `<id>.sops.yaml` file per item under a synced directory, encrypted to an
# age identity. On this repository that identity is a YubiKey PIV slot, so the token is the unlock.
#
# ## The unit is a USER unit, not a system one
#
# `rosecd` claims `org.freedesktop.secrets` on the **session** bus and reads `~/.config/rosec/
# config.toml`. It shells out to `sops` and to `age-plugin-yubikey`, so both must be on its `PATH`;
# the unit adds them ahead of the system profile rather than trusting the profile.
#
# ## A name clash with KeePassXC, until the migration lands
#
# KeePassXC also claims `org.freedesktop.secrets`. Two units cannot hold the name at once, and the
# one that loses is killed by systemd. So this module is off by default: `enable` defaults to
# `false`, and a host flips one line after
# `docs/tasks/2026-11/keepassxc-to-rosec-migration/` has moved its entries and retired the KDBX
# provider. `kdn.services.rosec.conflictNotification.enable` is independent of `enable`: the
# notification reports the *store*, not the daemon, so it may run while the store is still being
# filled.
{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.services.rosec;

  # The provider config, rendered as TOML. `pkgs.formats.toml` drops a `null` key, so an unset
  # `age_recipient` writes no line at all, and the store's own `.sops.yaml` then chooses the
  # recipients.
  configFormat = pkgs.formats.toml { };

  providerOptions = {
    key_file = cfg.providers.sops.key_file;
    sops_binary = cfg.providers.sops.sops_binary;
    probe_timeout_seconds = cfg.providers.sops.probe_timeout_seconds;
  }
  // lib.optionalAttrs (cfg.providers.sops.age_recipient != null) {
    age_recipient = cfg.providers.sops.age_recipient;
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

  # `sops` and the age plugin are resolved from `PATH`: `rosecd` runs `sops` as a subprocess,
  # and `sops` runs the age plugin. `key_file` is exported too, so a manual `sops` run in the
  # same session honours the same identity.
  # `rosecd` mounts FUSE filesystems and shells out to `fusermount3`. The store copy is not
  # setuid, so the mount fails with EPERM; the NixOS wrapper at `/run/wrappers/bin` is setuid root
  # and must come first on `PATH`.
  servicePath = lib.concatStringsSep ":" [
    "/run/wrappers/bin"
    (lib.makeBinPath (
      [
        cfg.package
        cfg.providers.sops.sopsPackage
        cfg.providers.sops.agePluginYubikeyPackage
        pkgs.fuse3
      ]
      ++ cfg.extraPackages
    ))
  ];

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
    # No `set -u` surprises: the script reads `HOME` and the state directory, and a unit always
    # provides both.
    text = builtins.readFile ./rosec-conflicts.sh;
  };

  needsHomeManager = cfg.enable || cfg.conflictNotification.enable;

  # A systemd path unit takes an absolute path or a unit specifier, not a `~/` prefix. `%h` is the
  # home directory, so the option keeps the `~/` form that the provider itself expands.
  systemdUnitPath =
    path: if lib.hasPrefix "~/" path then "%h/${lib.removePrefix "~/" path}" else path;
in
{
  options.kdn.services.rosec = {
    enable = lib.mkEnableOption ''
      the rosec Secret Service daemon. Keep this `false` on a host where KeePassXC claims
      `org.freedesktop.secrets`: two units cannot hold that bus name
    '';

    package = lib.mkOption {
      type = lib.types.package;
      default = kdnConfig.inputs.rosec.packages.${pkgs.stdenv.hostPlatform.system}.rosec;
      defaultText = lib.literalExpression "kdnConfig.inputs.rosec.packages.\${system}.rosec";
      description = ''
        The rosec package. The default is the fork's own flake output, so the daemon and the
        `rosec` CLI cannot drift apart.
      '';
    };

    extraPackages = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
      description = ''
        Extra packages on the unit `PATH`. Use it for a provider that shells out to a binary this
        module does not add (a cloud CLI, a vault client).
      '';
    };

    providers.sops.id = lib.mkOption {
      type = lib.types.str;
      default = "sops";
      description = "The provider id. It names the provider in `rosec provider <id> unlock`.";
    };

    providers.sops.path = lib.mkOption {
      type = lib.types.str;
      example = "~/Nextcloud/drag0nius@nc.nazarewk.pw/important/rosec-storage";
      description = ''
        The store root: one directory per collection, one `<id>.sops.yaml` per item. A `~/` prefix
        is accepted and expanded by the provider.

        This is a `str`, not a `path`: the store lives in a synced directory under the home
        directory, and copying it into the Nix store at evaluation time would be wrong.
      '';
    };

    providers.sops.key_file = lib.mkOption {
      type = lib.types.str;
      default = "~/.config/sops/age/keys.txt";
      description = ''
        The age identity file. The provider exports it as `SOPS_AGE_KEY_FILE` for every `sops`
        call it makes.
      '';
    };

    providers.sops.age_recipient = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      example = "age1yubikey1q25g9xpunct74wnn29dgcgep78q666dkhpfg2flltg92fvyrew02j28464d";
      description = ''
        The recipient for new and changed files. A comma-separated list is allowed. `null` lets a
        `.sops.yaml` in the store root choose the recipients instead.

        An update encrypts to the union of this list and the recipients already in a file header,
        so this value can add access but never narrow it.
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
      defaultText = lib.literalExpression "pkgs.sops";
      description = "The `sops` package placed on the unit `PATH`.";
    };

    providers.sops.agePluginYubikeyPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.age-plugin-yubikey;
      defaultText = lib.literalExpression "pkgs.age-plugin-yubikey";
      description = ''
        The age plugin package placed on the unit `PATH`. A non-YubiKey identity needs no plugin,
        and an unused one on `PATH` costs nothing.
      '';
    };

    providers.sops.probe_timeout_seconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = ''
        The ceiling for the decrypt that `unlock` runs to prove the identity works. A wrong token
        then fails at unlock instead of on the first read.
      '';
    };

    ssh_fuse = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Mount the SSH-agent FUSE filesystem. `false` is the default on this repository: the
        provider-independent switch is off, and `ssh-agent.service` already serves the agent
        socket.
      '';
    };

    conflictNotification.enable = lib.mkEnableOption ''
      a desktop notification and a persistent state file for every sops-store conflict. It
      reports the store, so it works while `enable` is still `false`
    '';

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
        collection directory does not trigger it. The scan reads file names only, so one minute is
        cheap even on a synced store.
      '';
    };

    conflictNotification.stateFile = lib.mkOption {
      type = lib.types.str;
      default = "~/.local/state/rosec/conflicts.json";
      description = ''
        The persistent conflict record. One entry per conflict, keyed by path, so a conflict is
        notified once and remembered until the file is gone.
      '';
    };

    conflictScript = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = conflictsScript;
      description = ''
        The `rosec-conflicts` command the units run. It lists the store for archived superseded
        copies and `.conflicts/*.md` markers, notifies once per new conflict, and rewrites the
        state file. `rosec-conflicts --list` prints the current conflicts.
      '';
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || cfg.providers.sops.path != "";
          message = "kdn.services.rosec.providers.sops.path must name the store root when `enable` is true";
        }
      ];
    }

    # The option tree exists in every context, but only a Home Manager evaluation can write a user
    # unit and a file under the home directory. A NixOS host forwards the values downward.
    #
    # The two `readOnly` outputs (`package` and `conflictScript`) are not forwarded: each evaluation
    # derives its own from the same defaults, and a `mkDefault` on a `readOnly` option aborts with
    # "read-only, but set multiple times".
    (kdnConfig.util.ifHMParent (
      lib.mkIf needsHomeManager {
        home-manager.sharedModules = [
          {
            kdn.services.rosec = lib.mkDefault (
              builtins.removeAttrs cfg [
                "package"
                "conflictScript"
              ]
            );
          }
        ];
      }
    ))

    (kdnConfig.util.ifHM (
      lib.mkMerge [
        # The `rosec` CLI and the conflict command reach the user profile, so a terminal can run
        # `rosec provider sops unlock` and `rosec-conflicts --list` without the daemon.
        {
          kdn.env.packages = [
            cfg.package
            cfg.conflictScript
          ];
        }

        # The provider config is also the CLI's config: `rosec-sops conflicts list|show|resolve`
        # reads `~/.config/rosec/config.toml` when `--store` is absent. Render it whenever this
        # module is active, not only when the daemon runs, or the CLI fails on a host that still
        # keeps its password manager on the bus.
        (lib.mkIf needsHomeManager {
          xdg.configFile."rosec/config.toml".source = rosecConfigFile;
        })

        (lib.mkIf cfg.enable {
          systemd.user.services.rosecd = {
            Unit = {
              Description = "rosec Secret Service daemon (sops file tree)";
              Documentation = [ "https://github.com/jmylchreest/rosec" ];
              # Headless: no `graphical-session.target`. The daemon serves CLI clients over SSH and
              # in a TTY too, so it follows the user manager alone.
              PartOf = [ "default.target" ];
              After = [ "default.target" ];
            };

            Service = {
              # `dbus` so systemd publishes `BusName` and a client that asks for
              # `org.freedesktop.secrets` activates the unit.
              Type = "dbus";
              BusName = "org.freedesktop.secrets";
              ExecStart = "${lib.getExe' cfg.package "rosecd"}";
              Environment = [
                "PATH=${servicePath}"
                "SOPS_AGE_KEY_FILE=${cfg.providers.sops.key_file}"
              ];
              Restart = "on-failure";
              RestartSec = 2;
              # A cold start waits for the YubiKey. Keep the bound wide enough for a slow token and
              # still bounded when the token is absent: the unit fails instead of hanging.
              TimeoutStartSec = "60s";
            };

            Install.WantedBy = [ "default.target" ];
          };
        })

        (lib.mkIf cfg.conflictNotification.enable {
          # The state directory exists before the first run, so the script writes one file and
          # never fails on a missing parent.
          home.file.".local/state/rosec/.keep".text = "";

          systemd.user.services.rosec-conflicts = {
            Unit.Description = "report rosec sops-store conflicts";

            Service = {
              Type = "oneshot";
              ExecStart = lib.escapeShellArgs [
                (lib.getExe cfg.conflictScript)
                "--store"
                cfg.providers.sops.path
                "--state"
                cfg.conflictNotification.stateFile
              ];
              Environment = [
                "PATH=${
                  lib.makeBinPath (
                    [ cfg.conflictScript ]
                    ++ lib.optional cfg.conflictNotification.notify pkgs.libnotify
                    ++ lib.optional cfg.conflictNotification.swaync pkgs.swaynotificationcenter
                  )
                }"
              ];
              # A synced directory may be offline. A failed scan is not worth a failed unit, and
              # the timer retries.
              SuccessExitStatus = [
                0
                2
              ];
            };
          };

          # Best-effort root-level fast route. `PathModified` covers `PathChanged` (it also fires
          # on a simple write), so one directive is enough.
          #
          # A systemd path unit watches one directory and is **not recursive**: a write inside
          # `<collection>/` changes that directory, not the store root, so the timer is the
          # reliable route. This unit still catches a new collection directory or a root-level
          # file, which is why it stays.
          #
          # Do not add `DirectoryNotEmpty`: it is level-triggered, and a store that holds any item
          # is never empty. The unit then re-fires after every scan until it hits the trigger limit
          # and fails, so the fast route dies on its first activation. A conflict present at login
          # is the timer's job instead (`OnStartupSec`).
          systemd.user.paths.rosec-conflicts = {
            Unit.Description = "watch the rosec sops store for conflict archives";
            Path = {
              PathModified = [ (systemdUnitPath cfg.providers.sops.path) ];
              # A burst of renames from the sync client must not queue a hundred scans. The bound
              # is wide enough for a normal sync and still stops a runaway loop.
              TriggerLimitBurst = 30;
              TriggerLimitIntervalSec = "60s";
            };
            Install.WantedBy = [ "default.target" ];
          };

          # The backstop: `inotify` misses a rename a sync client makes through its own temporary
          # file, so a timer rescans on a schedule anyway. The script dedupes, so the two routes
          # cannot notify twice for one conflict.
          systemd.user.timers.rosec-conflicts = {
            Unit.Description = "periodic rosec sops-store conflict scan";
            Timer = {
              # A conflict present at login is reported within a minute, without waiting for the
              # first periodic run.
              OnStartupSec = "1min";
              OnUnitActiveSec = cfg.conflictNotification.interval;
              Unit = "rosec-conflicts.service";
            };
            Install.WantedBy = [ "timers.target" ];
          };
        })
      ]
    ))
  ];
}

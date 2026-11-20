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

  # The daemon unit is emitted by the *host* evaluation: a NixOS host owns the user units it
  # forwards, and a desktop name holder lives there too. Emitting it from Home Manager as well
  # would shadow the holder in `~/.config/systemd/user` and lose its session ordering.
  rosecdUnit = {
    aliases = lib.optional (cfg.rosecd.unitName != "rosecd") "rosecd.service";
    # A desktop name holder supplies its own description; keep this one a default.
    description = lib.mkDefault "rosec Secret Service daemon (sops file tree)";
    documentation = [ "https://github.com/jmylchreest/rosec" ];
    partOf = [ "default.target" ];
    # Do NOT order after `default.target` while also being `WantedBy` it: systemd reports
    # "Transaction order is cyclic" when the target is restarted.
    after = lib.optional cfg.providers.sops.keyGeneration.enable "rosec-keys.service";
    wants = lib.optional cfg.providers.sops.keyGeneration.enable "rosec-keys.service";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "dbus";
      BusName = "org.freedesktop.secrets";
      # The module owns the process; a name holder only contributes the unit shell.
      ExecStart = lib.mkForce "${lib.getExe' cfg.package "rosecd"}";
      Environment = [
        "PATH=${servicePath}"
        "SOPS_AGE_KEY_FILE=${cfg.providers.sops.key_file}"
        # The package's unit carries this; re-declaring the unit must not drop it.
        "RUST_LOG=info"
      ];
      Restart = "on-failure";
      RestartSec = 2;
      LimitMEMLOCK = "infinity";
      TimeoutStartSec = lib.mkDefault "60s";
    };
  };

  unlockUnit = {
    description = "Unlock the rosec sops store after the Secret Service daemon starts";
    requires = [ "${cfg.rosecd.unitName}.service" ];
    after = [ "${cfg.rosecd.unitName}.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "120s";
      ExecStart = "${pkgs.writeShellScript "rosec-unlock" ''
        set -eu
        ${pkgs.expect}/bin/expect -c '
          set timeout 90
          spawn ${lib.getExe' cfg.package "rosec"} unlock
          expect {
            -re "Press Enter|No password needed" { send "\r"; exp_continue }
            timeout { exit 1 }
            eof
          }
        ' || exit 1
        # `expect` exits 0 at EOF even when the prompt never appeared; the daemon is the only
        # authority on whether the store is open.
        ${lib.getExe' cfg.package "rosec"} status | ${pkgs.gnugrep}/bin/grep -q "sops.*unlocked" \
          || exit 1
      ''}";
    };
  };

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
        pkgs.age-plugin-tpm
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

  # The same generator the sops-nix setup uses (`age-plugin-yubikey`), filtered to the unattended
  # slot. The full `keys.txt` carries slots 1, 2 and 3, and `sops` starts one plugin process per
  # identity; the rosec key file therefore keeps only the slot the master is wrapped to.
  keyGenScript = pkgs.writeShellApplication {
    name = "rosec-age-gen-keys-yubikey";
    runtimeInputs = [
      cfg.providers.sops.agePluginYubikeyPackage
      pkgs.gnugrep
    ];
    text = ''
      age-plugin-yubikey --identity --slot ${toString cfg.providers.sops.keyGeneration.slot} \
        | grep '^AGE-PLUGIN-YUBIKEY-' || :
    '';
  };

  # The sops-nix pre-start merge, as a user service: keep every existing line, append what the
  # generators print, sort and de-duplicate. The file is user-owned (0600), unlike the root-owned
  # `/var/lib/sops-nix/key.txt`.
  keyFileShell =
    let
      raw = cfg.providers.sops.keyGeneration.keyFile;
    in
    if lib.hasPrefix "~/" raw then "\"$HOME/${lib.removePrefix "~/" raw}\"" else lib.escapeShellArg raw;

  keyMergeScript = pkgs.writeShellApplication {
    name = "rosec-keys-merge";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
    ];
    text = ''
      umask 077
      keyFile=${keyFileShell}
      mkdir -p "$(dirname "$keyFile")"
      touch "$keyFile"
      {
        cat "$keyFile"
      ${lib.concatMapStringsSep "\n" (
        script: "  ${lib.getExe script} || true"
      ) cfg.providers.sops.keyGeneration.scripts}
      } | sed '/^[[:space:]]*$/d' | sort -u > "$keyFile.tmp"
      mv "$keyFile.tmp" "$keyFile"
      chmod 600 "$keyFile"
    '';
  };

  needsHomeManager =
    cfg.enable || cfg.conflictNotification.enable || cfg.providers.sops.keyGeneration.enable;

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

    rosecd.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.kdn.services.rosec.enable;
      defaultText = lib.literalExpression "config.kdn.services.rosec.enable";
      description = ''
        Install the daemon unit. Turn it off when another unit runs the same binary and owns
        `org.freedesktop.secrets`: two `Type=dbus` units cannot hold one bus name. The provider
        config and the key services still render.
      '';
    };

    rosecd.unitName = lib.mkOption {
      type = lib.types.str;
      default = "rosecd";
      description = ''
        Name of the daemon unit. A desktop that already has a D-Bus name holder can point this at
        it, and the module then supplies the process, environment and activation alias while the
        holder keeps its `Type=dbus`/`BusName` and session ordering. The unit always answers to
        `rosecd.service` as an alias.
      '';
    };

    rosecd.unlock.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.kdn.services.rosec.rosecd.enable;
      defaultText = lib.literalExpression "config.kdn.services.rosec.rosecd.enable";
      description = ''
        Install `rosec-unlock.service`, a oneshot that unlocks the store after the daemon starts.
        A locked provider blocks the first Secret Service client, and rosec has no silent unlock
        path; clients that start on their own should `Wants` this unit.
      '';
    };

    servicePath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      description = "`PATH` for a unit that runs the daemon outside this module.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      # The fork publishes Linux packages only. A Darwin host imports this module through the
      # universal profile with rosec off by default, so the option still has to evaluate there.
      # The placeholder keeps the evaluation green and makes an accidental enable fail loudly at
      # runtime instead of at build time.
      default =
        let
          system = pkgs.stdenv.hostPlatform.system;
          packages = kdnConfig.inputs.rosec.packages;
        in
        if packages ? ${system} then
          packages.${system}.rosec
        else
          # A directory package, not a bare script: `home.packages` merges this into a
          # `buildEnv`, and a single file at the store root cannot be merged.
          pkgs.runCommand "rosec-unavailable" { } ''
            mkdir -p $out/bin
            for name in rosec rosecd; do
              cat > $out/bin/$name <<'SH'
            #!/bin/sh
            echo "rosec is not packaged for this system; disable kdn.services.rosec or set its package" >&2
            exit 1
            SH
              chmod 0555 $out/bin/$name
            done
          '';
      defaultText = lib.literalExpression "kdnConfig.inputs.rosec.packages.\${system}.rosec, with a Darwin placeholder";
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
        call it makes. In `derived` mode it is used **only** to unwrap the master identity, once
        per session; item files then use the derived identity.
      '';
    };

    providers.sops.identity_file = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        The sops-encrypted **master identity** file of a `derived`-mode store, relative to the
        store root (for example `~/…/rosec-storage/.rosec-store-identity.sops.yaml`). Empty means
        the store is `direct`: item files are encrypted to the unlock keys themselves.

        The store mode is recorded in `<store>/.rosec-store.yaml` and is fixed at creation; the
        provider refuses a mismatch between this option and the store metadata. Change modes only
        by migrating to a new store (`rosec-sops store migrate`).
      '';
    };

    providers.sops.identity_key_file = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        The key used **only** to unwrap `identity_file`. Empty reuses `key_file`. A PGP/KMS
        master rule ignores this age key file; sops uses its own key source for that rule.
      '';
    };

    providers.sops.runtime_identity_file = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Where the unwrapped master identity is written while the provider is unlocked. Empty uses
        the provider default, `$XDG_RUNTIME_DIR/rosec/store-identity.age` (mode 0600). `lock`
        removes it.
      '';
    };

    providers.sops.keyGeneration.enable = lib.mkEnableOption ''
      merge the YubiKey age identities into the rosec key file, using the same
      `age-plugin-yubikey` generator as the sops-nix setup
    '';

    providers.sops.keyGeneration.slot = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = ''
        The PIV slot of the unattended YubiKey identity. The repository's `yk-*-unattended`
        recipients are slot 3.
      '';
    };

    providers.sops.keyGeneration.keyFile = lib.mkOption {
      type = lib.types.str;
      default = cfg.providers.sops.key_file;
      description = ''
        Where the merged identities are written. Defaults to `key_file`. The service runs as the
        user, so this is a user-owned file (mode 0600), not the root-owned sops-nix key file.
      '';
    };

    providers.sops.keyGeneration.scripts = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ keyGenScript ];
      description = ''
        One script per identity source. Each prints age private keys on stdout and nothing when its
        source is absent. The default is the slot-3 YubiKey generator. Add the merged
        `kdn.security.secrets.age.genScripts` package to also include the sops-nix sources.
      '';
    };

    providers.sops.age_recipient = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      example = "age1yubikey1q25g9xpunct74wnn29dgcgep78q666dkhpfg2flltg92fvyrew02j28464d";
      description = ''
        The recipient for new and changed files. In `direct` mode this is the YubiKey (or other
        unlock key) recipient; in `derived` mode it is the **derived public key** printed by
        `rosec-sops identity init`. A comma-separated list is allowed. `null` lets a `.sops.yaml`
        in the store root choose the recipients instead.

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
      # Defined in every context: a NixOS host uses it to run the daemon from a unit it owns,
      # and the Home Manager evaluation must see the same value.
      kdn.services.rosec.servicePath = servicePath;
    }

    # The option tree exists in every context, but only a Home Manager evaluation can write a user
    # unit and a file under the home directory. A NixOS host forwards the values downward.
    #
    # The `readOnly` outputs (`conflictScript` and `servicePath`) are not forwarded: each evaluation
    # derives its own from the same defaults, and a `mkDefault` on a `readOnly` option aborts with
    # "read-only, but set multiple times".
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.rosecd.enable {
        systemd.user.services."${cfg.rosecd.unitName}" = rosecdUnit;
        systemd.user.units."rosecd.socket".enable = false;
        systemd.user.services.rosec-unlock = lib.mkIf cfg.rosecd.unlock.enable unlockUnit;
      }
    ))

    (kdnConfig.util.ifHMParent (
      lib.mkIf needsHomeManager {
        home-manager.sharedModules = [
          {
            kdn.services.rosec = lib.mkDefault (
              builtins.removeAttrs cfg [
                "package"
                "conflictScript"
                "servicePath"
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
          ]
          ++ lib.optional cfg.providers.sops.keyGeneration.enable keyGenScript;
        }

        # The provider config is also the CLI's config: `rosec-sops conflicts list|show|resolve`
        # reads `~/.config/rosec/config.toml` when `--store` is absent. Render it whenever this
        # module is active, not only when the daemon runs, or the CLI fails on a host that still
        # keeps its password manager on the bus.
        (lib.mkIf needsHomeManager {
          # `xdg.configFile` links a read-only store file, so the config is mode 0444 and
          # `rosecd` warns about it. Replace the link with a 0600 copy on every activation; the
          # file holds paths only, but the daemon should not have to warn at every start.
          home.activation.rosec-config-mode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            cfg="$HOME/.config/rosec/config.toml"
            if [ -L "$cfg" ]; then
              cp --remove-destination "$(readlink -f "$cfg")" "$cfg"
            fi
            chmod 600 "$cfg"
          '';
          xdg.configFile."rosec/config.toml".source = rosecConfigFile;
        })

        # The sops-nix analogue for the user-owned rosec key file: run the same
        # `age-plugin-yubikey` generator and merge the identities on login, so a YubiKey plugged
        # into this machine is discovered without a hand-written `rosec-keys.txt`.
        (lib.mkIf cfg.providers.sops.keyGeneration.enable {
          systemd.user.services.rosec-keys = {
            Unit.Description = "merge the YubiKey age identities into the rosec key file";
            # The merge is idempotent and the path unit already bounds a burst; the service's own
            # start limit would turn a dock's device burst into a failed unit.
            Unit.StartLimitIntervalSec = 0;
            Service = {
              Type = "oneshot";
              ExecStart = lib.getExe keyMergeScript;
            };
            Install.WantedBy = [ "default.target" ];
          };

          # `/dev/bus/usb` changes when a USB device node appears or disappears; that is the
          # edge-triggered plug/unplug signal. Do not watch `/dev`: it is written every second
          # (`/dev/null` and friends), so the non-recursive watch hits the trigger limit. Do not use
          # `PathExistsGlob=/dev/hidraw*`: it is level-triggered and re-fires after every run.
          systemd.user.paths.rosec-keys = {
            Unit.Description = "watch the USB bus to discover a YubiKey";
            Path = {
              PathChanged = [ "/dev/bus/usb" ];
              Unit = "rosec-keys.service";
              # A hub or a dock can present several device nodes at once.
              TriggerLimitBurst = 10;
              TriggerLimitIntervalSec = "60s";
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

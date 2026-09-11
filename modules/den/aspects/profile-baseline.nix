# The `profile/machine/baseline` module of the old tree, as three den aspects.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# `profile-baseline` is the root bundle of the machine layer. Every other machine bundle reaches it.
# It names the aspects a managed machine needs, and it carries the boot, initrd, network and
# OpenSSH opinions of the old module.
#
# ## Class list
#
#   - `profile-baseline` — `nixos`, `darwin` and `homeManager`
#   - `profile-baseline-gc` — `nixos` and `darwin`
#   - `profile-baseline-flake-links` — `nixos`
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The 12 `enable` writes become `includes` entries.**
# 3. **`garbageCollection.enable` becomes `profile-baseline-gc`.** A reachable `enable` breaks rule
#    2, so the switch becomes a leaf aspect. A consumer that runs its own collector drops the name.
# 4. **`flakeCheckoutLinks.enable` becomes `profile-baseline-flake-links`.** Same reason.
# 5. **`primaryUser.profile` and `primaryUser.enable` go.** The old default of `primaryUser.profile`
#    at `baseline/default.nix:39` is one person's login name. A den host names its own users through
#    `kdn.users`, so no bundle names a person.
# 6. **Both inline password hashes go.** `baseline/default.nix:316` inlines the root hash. The port
#    reads a **file** instead, through `kdn.profile-baseline.rootHashedPasswordFile`.
#    `baseline/default.nix:269` inlines the initrd emergency-access hash. nixpkgs declares
#    `boot.initrd.systemd.emergencyAccess` as `oneOf [ bool (nullOr (passwdEntry str)) ]` and offers
#    no `…File` variant, because the value goes into the initrd shadow line. So the port keeps a
#    string option with a `null` default, and the consumer supplies the value from its own data.
# 7. **The known-hosts payload becomes an option.** `baseline/default.nix:393` names a file next to
#    the old module, and that file holds a personal host list. The port declares
#    `kdn.profile-baseline.knownHostsFiles`, default `[ ]`.
# 8. **`environment.etc."kdn/source-flake"` goes.** The old line reads `kdnConfig.self`, the flake
#    itself. An aspect sees no flake, so the consumer writes that entry in its own host config.
# 9. **`kdn.security.disk-encryption.enable` resolves here.** That old module is 27 lines and writes
#    two things: `kdn.toolset.fs.encryption.enable` and `security.tpm2.enable`. This bundle names
#    `toolset-fs-encryption` and writes `security.tpm2.enable`, so the area needs no aspect of its
#    own. It closes a gap that `docs/den-universal-mapping.md` records.
# 10. **`kdn.fs.zfs.enable` goes.** `fs-zfs` needs a unique `networking.hostId`, which is a machine
#     fact. A den host names its own storage. See the plan's `## Not planned, and why`.
# 11. **The overlay-network block goes.** `baseline/default.nix:443-455` names real network clients
#     and index numbers. Those belong to the `net-netbird` options and to the host entity.
# 12. **`kdn.env.packages` goes.** Each target writes the native package option of its own class,
#     through ../common/filter-packages.nix.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.**
# 2. **No reachable `enable` option.** See changes 3 and 4.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ inputs, kdn, ... }:
let
  # The options, shared by every class. An import dedupes by path.
  declaration =
    { lib, ... }:
    {
      options.kdn.profile-baseline.initrd.emergency.rebootTimeout = lib.mkOption {
        type = lib.types.int;
        default = 0;
        example = 30;
        description = ''
          How many seconds the initrd emergency shell waits for a key press. It reboots when the
          time runs out. A value of `0` turns the wait off, and the shell then waits forever.
        '';
      };

      options.kdn.profile-baseline.initrd.emergencyAccess = lib.mkOption {
        type = with lib.types; nullOr (either bool str);
        default = null;
        example = false;
        description = ''
          What the initrd emergency shell accepts. `null` leaves the nixpkgs default alone, so the
          shell refuses every login.

          A string is a hashed super-user password. nixpkgs writes it straight into the initrd
          shadow line, and it offers no file-based variant. So a consumer that wants authenticated
          emergency access reads the hash from its own data and sets it here. The hash never
          belongs in a module file.
        '';
      };

      options.kdn.profile-baseline.rootHashedPasswordFile = lib.mkOption {
        type = with lib.types; nullOr path;
        default = null;
        example = "/run/secrets/root-password-hash";
        description = ''
          A file that holds the hashed root password. `null` leaves the root account locked.

          The old module inlines the hash. A file keeps the value out of the store and out of every
          commit.
        '';
      };

      options.kdn.profile-baseline.knownHostsFiles = lib.mkOption {
        type = with lib.types; listOf path;
        default = [ ];
        description = ''
          Extra `ssh_known_hosts` files this machine trusts.

          The old module names a file next to itself, and that file lists real hosts. A host list is
          personal, so the consumer names its own file here.
        '';
      };
    };

  packages =
    pkgs: with pkgs; [
      git
      bash
      curl
      jq
      sshfs

      nix-derivation # pretty-derivation
      nix-output-monitor
      nix-du
      nix-tree
    ];

  filtered = lib: pkgs: import ../common/filter-packages.nix { inherit lib; } (packages pkgs);

  # The options of the garbage-collection leaf. Both classes import it, and an import dedupes by
  # path, so the declaration lands once per consumer.
  gcDeclaration =
    { lib, ... }:
    {
      options.kdn.profile-baseline-gc.dryRun = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Make angrr report and delete nothing. It adds `--dry-run` to
          `services.angrr.extraArgs`, and it raises `services.angrr.logLevel` to `debug` so the
          log names each skipped root.

          The default is `true`, because angrr deletes and a consumer must read one report before
          the first real pass. Read the report, then set this to `false`.
        '';
      };
    };
in
{
  kdn.profile-baseline.includes = [
    kdn.dev-git
    kdn.dev-shell
    kdn.hw-usbip
    kdn.hw-yubikey
    kdn.locale
    kdn.net-dynamic-hosts
    kdn.net-resolved
    kdn.profile-baseline-flake-links
    kdn.profile-baseline-gc
    kdn.profile-headless
    kdn.program-direnv
    kdn.secrets
    kdn.toolset-fs-encryption
  ];

  kdn.profile-baseline.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.profile-baseline;
    in
    {
      imports = [ declaration ];

      config = lib.mkMerge [
        {
          environment.systemPackages = filtered lib pkgs ++ [
            pkgs.dracut
            (pkgs.writeShellApplication {
              name = "kdn-systemd-find-cycles";
              runtimeInputs = [ pkgs.systemd ];
              text = ''
                systemd_args=()
                dot_args=()
                reading_dot=1
                for arg in "$@"; do
                  if test "$arg" == "--" ; then
                    test "$reading_dot" == 0 && reading_dot=1 || reading_dot=0
                  elif test "$reading_dot" == 1 ; then
                    dot_args+=("$arg")
                  else
                    systemd_args+=("$arg")
                  fi
                done
                systemd-analyze dot --no-pager --order "''${systemd_args[@]}" | systemd-find-cycles "''${dot_args[@]}"
              '';
            })
          ];
        }
        {
          # `security.tpm2` and the `toolset-fs-encryption` inclusion together replace the whole
          # 27-line `security/disk-encryption` module of the old tree. The old line writes a plain
          # `true`; a `mkDefault` here lets a host refuse it.
          security.tpm2.enable = lib.mkDefault true;
        }
        {
          # Native /etc/subuid + /etc/subgid management through services.userborn.
          #
          # userborn generates the per-user subordinate range (auto from `autoSubUidGidRange`, or
          # explicit through `subUidRanges`/`subGidRanges`) into `passwordFilesLocation`, and it
          # bind-mounts the files read-only into /etc — `newuidmap` refuses a symlink. So
          # `setup-etc` must NOT own the same files through `environment.etc`: a declaration there
          # fights the bind mount and it breaks activation. Rootless podman needs only the per-user
          # range userborn allocates, so no manual range is needed.
          services.userborn.enable = lib.mkDefault true;
          services.userborn.passwordFilesLocation = "/var/lib/nixos/userborn/etc";
        }
        {
          hardware.enableRedistributableFirmware = lib.mkDefault true;
          boot.initrd.systemd.emergencyAccess = lib.mkIf (
            cfg.initrd.emergencyAccess != null
          ) cfg.initrd.emergencyAccess;
          boot.initrd.systemd.enable = lib.mkDefault true;
          boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
          boot.loader.systemd-boot.configurationLimit = 10;
          boot.loader.systemd-boot.enable = lib.mkDefault true;
          boot.tmp.cleanOnBoot = lib.mkDefault (!config.boot.tmp.useTmpfs);
          boot.tmp.useTmpfs = lib.mkDefault true;
          boot.tmp.tmpfsSize = lib.mkDefault "10%";
          boot.initrd.systemd.users.root.shell = lib.getExe pkgs.bashInteractive;
          boot.initrd.systemd.storePaths = [ (lib.getExe pkgs.bashInteractive) ];
          boot.initrd.systemd.initrdBin = with pkgs; [
            gnugrep
            gnused
            coreutils
            findutils
            moreutils
            which
          ];
        }
        {
          networking.nftables.enable = lib.mkDefault true;
          networking.networkmanager.appendNameservers = [ ];
          networking.nameservers = lib.mkIf (!config.networking.networkmanager.enable) (
            with config.networking.networkmanager; insertNameservers ++ appendNameservers
          );
          networking.networkmanager.enable = lib.mkDefault true;
          networking.networkmanager.logLevel = lib.mkDefault "INFO";
          systemd.network.enable = lib.mkDefault true;
          networking.useNetworkd = lib.mkDefault true;
          systemd.network.wait-online.enable = lib.mkDefault (
            lib.attrsets.filterAttrs (
              _: net: !(net.linkConfig.Unmanaged or false)
            ) config.systemd.network.networks != { }
          );
          systemd.network.wait-online.anyInterface = lib.mkDefault true;
          systemd.network.config.networkConfig.UseDomains = lib.mkDefault true;
        }
        {
          services.openssh.enable = lib.mkDefault true;
          services.openssh.openFirewall = lib.mkDefault true;
          services.openssh.settings.PasswordAuthentication = lib.mkDefault false;
          services.openssh.settings.GatewayPorts = "clientspecified";
          programs.ssh.extraConfig = lib.mkBefore ''
            Include /etc/ssh/ssh_config.d/*.config
          '';
          programs.ssh.knownHostsFiles = cfg.knownHostsFiles;
          location.provider = "geoclue2";
          users.mutableUsers = false;
          users.users.root.hashedPasswordFile = lib.mkIf (
            cfg.rootHashedPasswordFile != null
          ) cfg.rootHashedPasswordFile;
          services.locate.enable = lib.mkDefault true;
          services.locate.package = pkgs.mlocate;
          services.locate.pruneBindMounts = lib.mkDefault true;
          services.avahi.enable = lib.mkDefault false;
          services.devmon.enable = false;
          boot.kernelParams = [ "consoleblank=90" ];
          boot.initrd.availableKernelModules = [
            "ahci"
            "nls_cp437"
            "nls_iso8859_1"
            "nls_iso8859_2"
            "nvme"
            "sd_mod"
            "uas"
            "usb_storage"
            "usbcore"
            "usbhid"
            "vfat"
            "xhci_hcd"
            "xhci_pci"
          ];
          environment.shellAliases =
            let
              commands = n: prefix: {
                "${n}" = prefix;
                "${n}c" = "${prefix} cat";
                "${n}r" = "${prefix} restart";
                "${n}s" = "${prefix} status";
                "${n}uS" = "${prefix} stop";
                "${n}us" = "${prefix} start";
                "${n}ur" = "${prefix} restart";
              };
            in
            {
              sj = "journalctl";
              uj = "journalctl --user";
            }
            // (commands "sc" "systemctl")
            // (commands "uc" "systemctl --user");
        }
        {
          environment.etc."ssh/ssh_config.d/00-kdn-profile-baseline.config".text = ''
            Match User nixos
              StrictHostKeyChecking no
              UpdateHostKeys no
              UserKnownHostsFile /dev/null
          '';
        }
        {
          # One per-user nix profile directory, so a normal user builds without root.
          systemd.tmpfiles.rules = lib.trivial.pipe config.users.users [
            lib.attrsets.attrValues
            (builtins.filter (u: u.isNormalUser))
            (map (
              user:
              let
                u = toString (user.uid or user.name);
                g = toString (user.gid or user.group);
              in
              [ "d /nix/var/nix/profiles/per-user/${user.name} 0750 ${u} ${g} - -" ]
            ))
            builtins.concatLists
          ];
        }
        (
          let
            timeout = cfg.initrd.emergency.rebootTimeout;
          in
          lib.mkIf (timeout > 0) {
            boot.initrd.systemd.services."emergency" = {
              overrideStrategy = "asDropin";
              postStart = ''
                if ! /bin/systemd-ask-password --timeout=${toString timeout} \
                  --no-output --emoji=no \
                  "Are you there? Press enter to enter emergency shell."
                then
                  /bin/systemctl reboot
                fi
              '';
            };
          }
        )
        (lib.mkIf (config.disko.enableConfig or false) {
          fileSystems."/boot".options = [
            "fmask=0077"
            "dmask=0077"
          ];
        })
        (lib.mkIf (config.kdn.security.secrets.allowed or false) {
          systemd.services.sops-install-secrets.postStart = ''
            chmod -R go+r /run/configs
          '';
        })
        (
          let
            kernelParams = [
              "systemd.log_level=debug"
              "systemd.debug_shell=1"
              "systemd.default_debug_tty=tty9"
              "rd.systemd.debug_shell=1"
              "rd.systemd.default_debug_tty=tty10"
            ];
          in
          lib.mkIf config.boot.initrd.systemd.enable {
            specialisation.emergency = {
              inheritParentConfig = true;
              configuration = {
                systemd.defaultUnit = lib.mkForce "emergency.target";
                system.nixos.tags = [ "emergency" ];
                boot.kernelParams = kernelParams;
              };
            };
            specialisation.rescue = {
              inheritParentConfig = true;
              configuration = {
                systemd.defaultUnit = lib.mkForce "rescue.target";
                system.nixos.tags = [ "rescue" ];
                boot.kernelParams = kernelParams;
              };
            };
            specialisation.boot-debug = {
              inheritParentConfig = true;
              configuration = {
                system.nixos.tags = [ "boot-debug" ];
                boot.kernelParams = kernelParams;
              };
            };
            systemd.services."debug-shell".overrideStrategy = "asDropinIfExists";
            boot.initrd.systemd.services."debug-shell".overrideStrategy = "asDropinIfExists";
          }
        )
      ];
    };

  kdn.profile-baseline.darwin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      config = lib.mkMerge [
        {
          environment.systemPackages = filtered lib pkgs;
          services.openssh.enable = lib.mkDefault true;
        }
        (lib.mkIf (config.kdn.security.secrets.allowed or false) {
          system.activationScripts.postActivation.text = lib.mkOrder 1501 ''
            chmod -R go+r /run/configs
          '';
        })
      ];
    };

  kdn.profile-baseline.homeManager =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];

      config.home.packages = filtered lib pkgs;
    };

  # The garbage-collection leaf. A consumer that runs its own collector drops this one name.
  kdn.profile-baseline-gc.nixos =
    { config, lib, ... }:
    {
      imports = [
        gcDeclaration
        inputs.angrr.nixosModules.angrr
      ];

      config = {
        nix.gc.automatic = lib.mkDefault true;
        # `nix-collect-garbage` with no option deletes only an unreachable store path. It never
        # deletes an old profile generation, and every generation is a collector root. So a stale
        # generation holds its whole closure forever, and `keep-outputs`/`keep-derivations` make
        # that closure much larger than the system itself.
        #
        # `--delete-older-than 7d` deletes each profile generation older than 7 days, then it
        # collects every path that loses its last root. It keeps the generation that was active 7
        # days ago, so one rollback target always survives.
        #
        # Nix has no age test for a store path. A profile generation is the only age-based handle
        # the built-in collector offers. An out-link such as `result` needs angrr instead.
        nix.gc.options = lib.mkDefault "--delete-older-than 7d";
        services.angrr.enable = lib.mkDefault true;
        # `services.angrr.enableNixGcIntegration` declares no default of its own, and angrr supplies
        # one only when `services.angrr.enable` is true. So this line stays unconditional. A guard
        # leaves the option undefined, and every read of it then fails.
        services.angrr.enableNixGcIntegration = lib.mkDefault true;
        services.angrr.settings.temporary-root-policies.direnv.path-regex = "/\\.direnv/";
        services.angrr.settings.temporary-root-policies.direnv.period = "7d";
        services.angrr.settings.temporary-root-policies.result.path-regex = "/result[^/]*$";
        services.angrr.settings.temporary-root-policies.result.period = "5d";
        # 24 of the 29 auto roots of the measured Darwin host live under `.devenv/`, and 13 of them
        # were last written between 43 and 105 days ago (measured 2026-09-11). The `direnv` policy
        # above cannot reach them: `.devenv` and `.direnv` are separate directories. So the largest
        # root class had no policy at all, and angrr keeps an unmatched root forever.
        #
        # 30 days sits inside a measured empty band. No root of that set is between 17 and 42 days
        # old, so this period reaps every dead project root and keeps every root of an active one.
        #
        # One trade-off: angrr reads the mtime of the link target, and devenv rewrites a link only
        # when the derivation changes. So a link of an active project can age out. devenv recreates
        # it on the next shell entry, so the cost is one rebuild, never lost work.
        services.angrr.settings.temporary-root-policies.devenv.path-regex = "/\\.devenv/";
        services.angrr.settings.temporary-root-policies.devenv.period = "30d";
        # The safe first state. `--dry-run` makes angrr print every verdict and remove no file.
        # `debug` adds the line that names each root a policy skips, and that miss is exactly the
        # `.devenv`-versus-`.direnv` defect the policy above closes.
        services.angrr.extraArgs = lib.mkIf config.kdn.profile-baseline-gc.dryRun [ "--dry-run" ];
        services.angrr.logLevel = lib.mkIf config.kdn.profile-baseline-gc.dryRun (lib.mkDefault "debug");
        services.angrr.settings.profile-policies.system.profile-paths = [
          "/nix/var/nix/profiles/system"
        ];
        services.angrr.settings.profile-policies.system.keep-since = "14d";
        services.angrr.settings.profile-policies.system.keep-latest-n = 5;
        services.angrr.settings.profile-policies.system.keep-booted-system = true;
        services.angrr.settings.profile-policies.system.keep-current-system = true;
        services.angrr.settings.profile-policies.user.enable = false;
        services.angrr.settings.profile-policies.user.profile-paths = [
          "~/.local/state/nix/profiles/profile"
          "/nix/var/nix/profiles/per-user/root/profile"
        ];
        services.angrr.settings.profile-policies.user.keep-since = "1d";
        services.angrr.settings.profile-policies.user.keep-latest-n = 1;
      };
    };

  kdn.profile-baseline-gc.darwin =
    { config, lib, ... }:
    {
      imports = [
        gcDeclaration
        inputs.angrr.darwinModules.angrr
      ];

      config = {
        nix.gc.automatic = lib.mkDefault true;
        nix.gc.options = lib.mkDefault "--delete-older-than 7d";
        # nix-darwin runs the collector weekly, on Sunday at 03:15
        # (`<nix-darwin>/modules/services/nix-gc/default.nix:34`). A 7-day threshold then takes up
        # to 14 days to act on a generation. NixOS runs it daily, because `nix.gc.dates` defaults
        # to `[ "03:15" ]`. Match that.
        nix.gc.interval = lib.mkDefault [
          {
            Hour = 3;
            Minute = 15;
          }
        ];
        services.angrr.enable = lib.mkDefault true;
        services.angrr.settings.temporary-root-policies.direnv.path-regex = "/\\.direnv/";
        services.angrr.settings.temporary-root-policies.direnv.period = "7d";
        services.angrr.settings.temporary-root-policies.result.path-regex = "/result[^/]*$";
        services.angrr.settings.temporary-root-policies.result.period = "5d";
        # See the `nixos` class above for the full reasoning behind the `devenv` policy and the
        # 30-day period.
        services.angrr.settings.temporary-root-policies.devenv.path-regex = "/\\.devenv/";
        services.angrr.settings.temporary-root-policies.devenv.period = "30d";
        # The safe first state, as in the `nixos` class.
        services.angrr.extraArgs = lib.mkIf config.kdn.profile-baseline-gc.dryRun [ "--dry-run" ];
        services.angrr.logLevel = lib.mkIf config.kdn.profile-baseline-gc.dryRun (lib.mkDefault "debug");
        # The one line that starts angrr on Darwin. `services.angrr.timer.enable` is the only
        # trigger there, because nix-darwin ships no `nix-gc.service` and the Darwin module
        # declares no `enableNixGcIntegration`. Without the timer the plist carries
        # `RunAtLoad = false` and no `StartCalendarInterval`, so the daemon never wakes up.
        #
        # `timer.dates` stays unset. The NixOS type is `str` and the Darwin type is
        # `listOf (attrsOf int)`, so no shared block can name it. Both defaults are 03:00.
        services.angrr.timer.enable = lib.mkDefault true;
        # launchd sends the output of a daemon to `/dev/null` when neither path is set, so the
        # dry-run report would be lost. nix-darwin uses the same pattern for its own daemons.
        launchd.daemons.angrr.serviceConfig.StandardOutPath = "/var/log/angrr.log";
        launchd.daemons.angrr.serviceConfig.StandardErrorPath = "/var/log/angrr.log";
      };
    };

  # The flake-checkout link leaf. It writes the three `/etc/nixos` links.
  kdn.profile-baseline-flake-links.includes = [ kdn.dev-nix ];

  kdn.profile-baseline-flake-links.nixos =
    { config, lib, ... }:
    let
      # One option names the checkout, so the literal cannot drift. `or null` keeps a lone
      # (aspect, class) pair resolvable — `dev-nix` declares the option in a real consumer.
      flakePath = config.kdn.dev-nix.flake.path or null;
    in
    {
      config = lib.mkIf (flakePath != null) {
        systemd.tmpfiles.rules = [
          "L /etc/nixos/flake.nix       - - - - flake.nix.rel"
          "L /etc/nixos/flake.nix.abs   - - - - ${flakePath}/flake.nix"
          "L /etc/nixos/flake.nix.rel   - - - - ../..${flakePath}/flake.nix"
        ];
      };
    };
}

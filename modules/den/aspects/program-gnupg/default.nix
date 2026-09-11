# `kdn.programs.gnupg`, as a den aspect. It ports `modules/universal/programs/gnupg/default.nix`.
#
# ## Why this aspect is a directory
#
# The old module reads two data files next to itself: `pass-pubkeys.sh` and `pcsc-lite-rules.js`. An
# aspect must hold its own data, so both files live next to this one.
#
# ## Two renames the aspect rules force
#
# `pass-secret-service.enable` and `passwordStore.enable` are reachable `enable` options, so each
# becomes `.use`. The old `kdn.programs.gnupg.enable` disappears: inclusion is the switch.
#
# ## Two writes the port drops
#
# The old module writes `home-manager.sharedModules` from its `nixos` branch, to turn the
# gnome-keyring user service off. den holds no such bridge, so the user-side write moves into the
# `homeManager` target under the same option.
#
# It also writes `systemd.user.services."dbus-org.freedesktop.secrets".requires` from
# `config.kdn.desktop.sway.systemd.envs.target`. The sway aspect belongs to another batch, so the
# aspect exposes `passSecretService.extraUnits` and a consumer names the target. Mark for owner review.
{ kdn, ... }:
let
  declaration =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.gnupg;
    in
    {
      options.kdn.programs.gnupg.pinentry = lib.mkOption {
        type = lib.types.package;
        default = pkgs.callPackage ../../../../packages/pinentry { };
        description = "The pinentry build the agent uses first.";
      };

      options.kdn.programs.gnupg.pass-secret-service.use = lib.mkEnableOption "pass-secret-service";

      options.kdn.programs.gnupg.passwordStore.use = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Install and configure `pass` next to the GnuPG agent.

          A consumer that already owns a password manager sets this to `false` and keeps the agent, the
          pinentry and the smartcard tooling.

          The old module names this option `passwordStore.enable`. An aspect holds no reachable
          `enable`, so the name changed and the behaviour did not.
        '';
      };

      options.kdn.programs.gnupg.disableGnomeKeyring = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Turn gnome-keyring off when `pass-secret-service` serves the Secret Service D-Bus name.

          Two secret services cannot own one name, so this repository turns gnome-keyring off. Set this
          option to `false` to keep gnome-keyring and lose the pass-backed secret service.
        '';
      };

      options.kdn.programs.gnupg.passSecretService.extraUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "kdn-sway-envs.target" ];
        description = ''
          Units the secret service unit requires and starts after. A desktop that exports the session
          environment names its own target here.

          Two plain definitions of this list concatenate. Never put `lib.mkDefault` on it.
        '';
      };

      config = { };
    };

  filterPackages = import ../../common/filter-packages.nix;

  packagesOf =
    lib: pkgs: cfg:
    let
      fallbackPinentry =
        if pkgs.stdenv.hostPlatform.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-all;
    in
    (filterPackages { inherit lib; }) [
      (lib.hiPrio cfg.pinentry)
      (lib.lowPrio fallbackPinentry)

      pkgs.opensc
      pkgs.pcsc-tools

      (pkgs.writeShellApplication {
        name = "pass-pubkeys";
        runtimeInputs = with pkgs; [
          pass
          gnupg
          gawk
        ];
        text = builtins.readFile ./pass-pubkeys.sh;
      })

      (pkgs.callPackage ../../../../packages/gpg-smartcard-reset-keys { })
    ];

  agentCommon =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      config.environment.systemPackages = packagesOf lib pkgs config.kdn.programs.gnupg;
      config.programs.gnupg.agent.enable = true;
      config.programs.gnupg.agent.enableSSHSupport = false;
    };
in
{
  kdn.program-gnupg.includes = [ kdn.apps ];

  kdn.program-gnupg.darwin = agentCommon;

  kdn.program-gnupg.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.gnupg;
      gpgSmartcardResetKeys = pkgs.callPackage ../../../../packages/gpg-smartcard-reset-keys { };
    in
    {
      imports = [ agentCommon ];

      config = lib.mkMerge [
        {
          services.pcscd.enable = true;
          hardware.gpgSmartcards.enable = true;
          programs.gnupg.agent.enableBrowserSocket = true;
          programs.gnupg.agent.enableExtraSocket = true;
          # The agent cannot remove a key, and the YubiKey GPG applet is either unset or set with an
          # unknown password.
          programs.gnupg.agent.pinentryPackage = cfg.pinentry;

          # Give usb-ip access to a YubiKey.
          security.polkit.extraConfig = builtins.readFile ./pcsc-lite-rules.js;

          systemd.user.services."gpg-agent" = {
            serviceConfig.Slice = "background.slice";
            # TODO: run it again when a smartcard comes back.
            postStart = ''
              if ! ${lib.getExe gpgSmartcardResetKeys} ; then
                echo 'WARNING: gpg-smartcard-reset-keys failed!'
              fi
            '';
          };
        }

        (lib.mkIf cfg.pass-secret-service.use (
          lib.mkMerge [
            {
              services.passSecretService.enable = true;
              services.passSecretService.package = pkgs.callPackage ../../../../packages/pass-secret-service { };
              systemd.user.services."dbus-org.freedesktop.secrets" = {
                aliases = [ "pass-secret-service.service" ];
                requires = cfg.passSecretService.extraUnits;
                after = [ "graphical-session-pre.target" ] ++ cfg.passSecretService.extraUnits;
                partOf = [ "graphical-session.target" ];
                serviceConfig = {
                  Restart = "on-failure";
                  RestartSec = 1;
                  ExecStartPost = "${lib.getExe' pkgs.coreutils "sleep"} 2";
                };
              };
            }
            # Two secret services cannot own one D-Bus name, so this block removes gnome-keyring. The
            # `lib.mkForce` stays: it beats a desktop module that turns gnome-keyring on. A consumer who
            # wants gnome-keyring sets `kdn.programs.gnupg.disableGnomeKeyring = false`.
            (lib.mkIf cfg.disableGnomeKeyring {
              services.gnome.gnome-keyring.enable = lib.mkForce false;
            })
          ]
        ))
      ];
    };

  kdn.program-gnupg.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.gnupg;
    in
    {
      imports = [ declaration ];

      config = lib.mkMerge [
        {
          home.packages = packagesOf lib pkgs cfg;

          programs.gpg.enable = true;
          programs.gpg.settings.no-throw-keyids = true;

          kdn.apps.gnupg = {
            enable = true;
            # The package list above holds the tooling.
            package.install = false;
            # The leading `/` makes the path relative to the home directory.
            dirs.data = [ "/.gnupg" ];
            dirs.config = [ "pinentry-kdn" ];
          };

        }

        # `kdn.apps-persist.directories` holds a plain string list, so it carries no file mode. The
        # old module writes `{ directory = ".gnupg"; mode = "0700"; }` into `kdn.disks.persist`. This
        # rule keeps the mode where the aspect can state it.
        #
        # The Home Manager `systemd.user.tmpfiles` module supports Linux alone. It fails the whole
        # evaluation on a darwin home, so the guard is mandatory. Measured 2026-09-11.
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          systemd.user.tmpfiles.rules = [
            "d %h/.gnupg 0700 - - -"
            "d %h/.config/pinentry-kdn 0700 - - -"
          ];
        })

        # `pass` is a separate concern from the agent, so it carries its own switch.
        (lib.mkIf cfg.passwordStore.use {
          programs.password-store.enable = true;
          programs.password-store.settings = {
            PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
            PASSWORD_STORE_CLIP_TIME = "10";
            # For Android interoperability. See
            # https://github.com/drduh/YubiKey-Guide/issues/152#issuecomment-852176877
            PASSWORD_STORE_GPG_OPTS = "--no-throw-keyids";
          };
        })

        # The user half of the gnome-keyring removal. The old module writes it from the `nixos` branch
        # through `home-manager.sharedModules`; den holds no such bridge.
        (lib.mkIf (cfg.pass-secret-service.use && cfg.disableGnomeKeyring) {
          services.gnome-keyring.enable = lib.mkForce false;
        })
      ];
    };
}

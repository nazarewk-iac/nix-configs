# The YubiKey and GnuPG smart-card setup, as a den aspect. It ports the `yubikey` module of the old
# hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs the YubiKey tools, it turns U2F on for PAM, it runs `pcscd` so a smart card answers, and
# it publishes the two pieces the age or SOPS setup needs: the `age-plugin-yubikey` plugin and one
# script that reads an age identity from a plugged-in key.
#
# ## Class list: `nixos`, `darwin` and `homeManager`
#
# The old module holds the package list outside every context guard, and it forwards itself into Home
# Manager with `ifHMParent`. It also holds an `ifHM` block for `scdaemon` and an
# `ifTypes [ "darwin" ]` block for the GnuPG agent. So all three classes carry real content:
#
#   - `nixos` — udev rules, the `plugdev` group, PAM U2F, `pcscd`, the `sops` ordering
#   - `darwin` — the packages and the GnuPG agent
#   - `homeManager` — the packages and the `scdaemon` settings
#
# ## What the port changes
#
# 1. **The `devices` option goes.** The old option's default reads a data file next to the module,
#    and that file holds the serial number of every real YubiKey. A serial is a personal hardware
#    identifier, and an aspect reads no file of the deprecated tree either. The option has **zero**
#    readers in the whole repository, measured 2026-09-11, so the drop changes no behaviour. The data
#    file stays at `modules/universal/hw/yubikey/yubikeys.nix` for the old tree.
# 2. **Two forward-writes become read-only publishers.** The old module writes
#    `kdn.security.secrets.age.plugins` and `kdn.security.secrets.age.genScripts`, which another area
#    declares. `den-eval-instantiate` forces each (aspect, class) pair **alone**, so a write to an
#    option no loaded module declares fails. Instead this aspect publishes
#    `kdn.hw.yubikey.agePlugins` and `kdn.hw.yubikey.ageGenScripts`, both read-only. The consumer
#    wires them:
#
#        kdn.security.secrets.age.plugins    = config.kdn.hw.yubikey.agePlugins;
#        kdn.security.secrets.age.genScripts = config.kdn.hw.yubikey.ageGenScripts;
#
# 3. **The GnuPG forward-write goes.** The old module writes `kdn.programs.gnupg.enable = mkDefault
#    true`. That option belongs to the `programs` area, so the consumer wires it. The `scdaemon`
#    settings this aspect writes stay, because `programs.gpg.*` is a plain Home Manager option.
# 4. **The desktop read becomes an own option.** The old module installs `yubioath-flutter` behind
#    `config.kdn.desktop.enable`. A den aspect declares no reachable `enable`, so the port declares
#    `kdn.hw.yubikey.graphical`.
# 5. **The `sops` ordering gets an existence gate.** `systemd.services.<name>` accepts any name, so a
#    class without `sops-nix` would get an empty `sops-install-secrets` unit. The port writes the two
#    lines only when `config ? sops`.
# 6. **The native option replaces the cross-platform package list.** A den target names its class, so
#    the host targets write `environment.systemPackages` and the Home Manager target writes
#    `home.packages`. The old module installs the same list in both places, and the port keeps that.
#
# ## `mkIf` inside a package list is real, and the port keeps it
#
# The old list holds `(lib.mkIf (!stdenv.hostPlatform.isDarwin) yubioath-flutter)`. The module system
# resolves a `mkIf` inside a list element: a true condition keeps the element, and a false condition
# removes it. Measured 2026-09-11 with `types.listOf types.package`. The port writes the same test as
# `lib.optional`, which is clearer and behaves the same. It matters for the `homeManager` class, which
# runs on Darwin too.
#
# ## Follow-up
#
# The old module carries a `TODO: run gpg-smartcard-reset-keys for users when plugging in or changing
# YubiKeys?`. That note stays open.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 4 above. `security.pam.u2f.enable`,
#    `services.pcscd.enable` and `programs.gnupg.agent.enable` belong to nixpkgs and to nix-darwin,
#    and the walk inspects the `kdn` prefix alone.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  # The three options. Every target imports this one module.
  declaration =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # `or true` keeps a lone (aspect, class) pair resolvable. The `secrets` aspect declares this
      # option for all three classes; a class that omits it reads the permissive answer.
      secretsAllowed = config.kdn.security.secrets.allowed or true;
    in
    {
      options.kdn.hw.yubikey.graphical = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          This machine runs a desktop, so the aspect adds the graphical authenticator
          `yubioath-flutter`.

          The old module reads `kdn.desktop.enable` here. A den aspect declares no reachable
          `enable`, so a consumer sets this option instead.

          `yubioath-flutter` is unsupported on `aarch64-darwin`, so a Darwin class installs nothing
          even when the value is `true`.
        '';
      };

      options.kdn.hw.yubikey.agePlugins = lib.mkOption {
        readOnly = true;
        type = lib.types.listOf lib.types.package;
        default = lib.optional secretsAllowed pkgs.age-plugin-yubikey;
        defaultText = lib.literalExpression "[ pkgs.age-plugin-yubikey ]";
        description = ''
          The age plugins a YubiKey needs. It is read-only.

          The old module writes this list straight into `kdn.security.secrets.age.plugins`, which
          another area declares. An aspect writes no option of another aspect, so the consumer wires
          it:

              kdn.security.secrets.age.plugins = config.kdn.hw.yubikey.agePlugins;

          The list is empty when `kdn.security.secrets.allowed` is `false`.
        '';
      };

      options.kdn.hw.yubikey.ageGenScripts = lib.mkOption {
        readOnly = true;
        type = lib.types.listOf lib.types.package;
        default = lib.optional secretsAllowed (
          pkgs.writeShellApplication {
            name = "kdn-sops-age-gen-keys-yubikey";
            runtimeInputs = with pkgs; [
              gnugrep
              age-plugin-yubikey
            ];
            runtimeEnv.ALLOW_ROOT_DEFAULT = "false";
            text = ''
              #: "''${ALLOW_ROOT:="$ALLOW_ROOT_DEFAULT"}"
              #if test "$ALLOW_ROOT" == false && test "$EUID" == 0 ; then
              #  echo "should not discover YubiKeys as root" >&2
              #  exit 0
              #fi
              age-plugin-yubikey --identity | grep '^AGE-PLUGIN-YUBIKEY-' || :
            '';
          }
        );
        defaultText = lib.literalExpression "[ <kdn-sops-age-gen-keys-yubikey> ]";
        description = ''
          The scripts that read an age identity from a plugged-in YubiKey. It is read-only.

          The old module writes this list straight into `kdn.security.secrets.age.genScripts`, which
          another area declares. The consumer wires it:

              kdn.security.secrets.age.genScripts = config.kdn.hw.yubikey.ageGenScripts;

          The list is empty when `kdn.security.secrets.allowed` is `false`. The root test inside the
          script stays commented out, exactly as the old module leaves it.
        '';
      };
    };

  basePackages =
    pkgs: with pkgs; [
      xkcdpass
      yubikey-manager
      yubikey-personalization
      yubico-pam
    ];
in
{
  kdn.hw-yubikey.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.hw.yubikey;

      secretsAllowed = config.kdn.security.secrets.allowed or true;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [
        declaration
        ../common/host-name.nix
      ];

      options.kdn.hw.yubikey.appId = lib.mkOption {
        type = lib.types.str;
        default = "pam://${config.kdn.hostName}";
        defaultText = lib.literalExpression ''"pam://" + config.kdn.hostName'';
        description = ''
          The PAM U2F application id and origin. A YubiKey binds a credential to this string, so a
          change to it invalidates every registered credential on this machine.
        '';
      };

      config = lib.mkMerge [
        {
          environment.systemPackages = filterPackages (
            basePackages pkgs
            ++ lib.optional (cfg.graphical && !pkgs.stdenv.hostPlatform.isDarwin) pkgs.yubioath-flutter
            ++ cfg.agePlugins
          );

          # `libfido2` brings https://github.com/Yubico/libfido2/blob/main/udev/70-u2f.rules
          services.udev.packages = with pkgs; [
            yubikey-personalization
            libfido2
          ];

          users.groups.plugdev = { };

          security.pam.u2f.enable = true;
          security.pam.u2f.settings.enable = true;
          security.pam.u2f.settings.cue = true;
          security.pam.u2f.settings.appid = cfg.appId;
          security.pam.u2f.settings.origin = cfg.appId;
        }
        (lib.mkIf secretsAllowed {
          services.pcscd.enable = true;
        })
        # `systemd.services` accepts any name, so a class without `sops-nix` would get an empty unit.
        # The `config ? sops` test keeps that from happening.
        (lib.mkIf (secretsAllowed && config ? sops) {
          systemd.services.sops-install-secrets.after = [ "pcscd.socket" ];
          systemd.services.sops-install-secrets.requires = [ "pcscd.socket" ];
        })
      ];
    };

  kdn.hw-yubikey.darwin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.hw.yubikey;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [ declaration ];

      # `yubioath-flutter` is unsupported on `aarch64-darwin`, so `graphical` adds nothing here.
      config.environment.systemPackages = filterPackages (basePackages pkgs ++ cfg.agePlugins);

      config.programs.gnupg.agent.enable = true;
    };

  kdn.hw-yubikey.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.hw.yubikey;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [ declaration ];

      config.home.packages = filterPackages (
        basePackages pkgs
        ++ lib.optional (cfg.graphical && !pkgs.stdenv.hostPlatform.isDarwin) pkgs.yubioath-flutter
        ++ cfg.agePlugins
      );

      config.programs.gpg.scdaemonSettings = {
        # `disable-ccid` makes a YubiKey answer. See
        # - https://support.yubico.com/hc/en-us/articles/360013714479-Troubleshooting-Issues-with-GPG
        # - https://dev.gnupg.org/T5451
        disable-ccid = true;
        pcsc-shared = true;

        # The PIN cache fix. See
        # - https://github.com/drduh/YubiKey-Guide/issues/135
        # - https://dev.gnupg.org/T3362
        # - https://dev.gnupg.org/T5436#148656
        disable-application = "piv";
      };
    };
}

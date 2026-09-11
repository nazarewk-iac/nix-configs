# The locale and the time zone of a machine, as a den aspect. It ports
# `modules/universal/locale/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It states one language opinion per machine and writes it into all three places that need it:
#
#   - a NixOS host gets `i18n.*` and `time.timeZone`
#   - a nix-darwin host gets `time.timeZone`, the Homebrew cask language and the login variables
#   - a Home Manager user gets `TZ`, the four `LC_*` variables and two `user-dirs` files
#
# Two later areas read one leaf of it: `desktop/sway` reads `xkbLayout` for the Sway `xkb_layout`
# input, and `profile/machine/desktop` reads the same leaf for `services.xserver.xkb.layout`. So the
# leaf ports before either of them.
#
# ## One declaration, three classes
#
# The seven options live in one module below, and each of the three targets imports it. Only one
# class loads per evaluation, so the module system sees exactly one declaration each time. A Home
# Manager user under a NixOS host is a second, separate evaluation, so that case is safe too.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch. The old NixOS and darwin halves sit behind
#    `lib.mkIf cfg.enable`; the Home Manager half never did. So the den targets are unconditional,
#    and the Home Manager behaviour does not move at all.
# 2. **`kdn.env.variables` does not survive.** A den target names its class, so the darwin target
#    writes `environment.variables` and the Home Manager target writes `home.sessionVariables`.
#    That is exactly the split the old `env` module made by hand.
# 3. **The old Home Manager half builds a local `config` shadow** to reuse the nixpkgs `i18n` names.
#    This port writes the four variables directly, so no shadow is needed.
#
# ## The trap this file respects
#
# **`timezone` stays `types.str`.** `null` cannot work: the Home Manager target writes the value
# into `home.sessionVariables.TZ`, and that option takes a string. A `nullOr` therefore stops the
# evaluation of every Home Manager user. An adopter changes the value; they cannot unset it.
#
# `extra` and `shorts` are `listOf`, so each one keeps this tree's value in its own `default` and
# neither carries a `lib.mkDefault`. A plain definition replaces a `mkDefault` default, but two
# plain definitions concatenate, so a `mkDefault` on a list would change what an adopter can do.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  # The seven options. Every target imports this one module.
  declaration =
    { config, lib, ... }:
    let
      cfg = config.kdn.locale;
    in
    {
      options.kdn.locale.timezone = lib.mkOption {
        type = lib.types.str;
        default = "Etc/UTC";
        example = "Europe/Warsaw";
        description = ''
          The time zone of the machine, as an IANA name.

          The type stays plain `str`. `null` cannot work here: the Home Manager target writes the
          value into `home.sessionVariables.TZ`, and that option takes a string. So an adopter
          changes the value; they cannot unset it.
        '';
      };

      options.kdn.locale.xkbLayout = lib.mkOption {
        type = lib.types.str;
        default = "us";
        example = "pl";
        description = ''
          The X keyboard layout. A desktop aspect reads it for the X server and for the Sway
          `xkb_layout` input setting.
        '';
      };

      options.kdn.locale.primary = lib.mkOption {
        type = lib.types.str;
        default = "en_GB.UTF-8";
        example = "en_US.UTF-8";
        description = ''
          The default locale. It becomes `LANG`, `LANGUAGE` and `LC_ALL`.
        '';
      };

      options.kdn.locale.extra = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          # see https://sourceware.org/git/?p=glibc.git;a=blob;f=localedata/SUPPORTED
          "C.UTF-8/UTF-8"
          "en_US.UTF-8/UTF-8"
          "en_GB.UTF-8/UTF-8"
        ];
        example = [ "pl_PL.UTF-8/UTF-8" ];
        description = ''
          Every locale a NixOS host builds, in the glibc `<locale>/<charset>` form.

          The list keeps `en_GB.UTF-8`, because `kdn.locale.primary` defaults to it. A
          `supportedLocales` list without the default locale breaks a NixOS host.

          The list stays an option default and never becomes a literal at the assignment site:
          `types.listOf` concatenates every definition, so a literal is a definition an adopter can
          add to but never remove.
        '';
      };

      options.kdn.locale.shorts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "en-GB"
          "en-US"
          "en"
        ];
        example = [ "en-US" ];
        description = ''
          The languages a Homebrew cask installs, in order of preference. Homebrew uses the short
          BCP-47 form, not the glibc form.
        '';
      };

      options.kdn.locale.time = lib.mkOption {
        type = lib.types.str;
        default = "en_GB.UTF-8";
        example = "en_US.UTF-8";
        description = ''
          The locale that formats a date and a time. It becomes `LC_TIME`.

          The default is `en_GB.UTF-8`, which starts a week on Monday.
        '';
      };

      options.kdn.locale.userDirs = lib.mkOption {
        type = lib.types.str;
        default = cfg.primary;
        defaultText = lib.literalExpression "config.kdn.locale.primary";
        description = ''
          The locale that names the XDG user directories. It goes into
          `~/.config/user-dirs.locale`.
        '';
      };
    };

  nixosTarget =
    { config, ... }:
    let
      cfg = config.kdn.locale;
    in
    {
      imports = [ declaration ];

      i18n.supportedLocales = cfg.extra;
      i18n.defaultLocale = cfg.primary;
      i18n.extraLocaleSettings = {
        LC_TIME = cfg.time;
        LANGUAGE = cfg.primary;
        LC_ALL = cfg.primary;
      };
      time.timeZone = cfg.timezone;
    };

  darwinTarget =
    { config, ... }:
    let
      cfg = config.kdn.locale;
    in
    {
      imports = [ declaration ];

      time.timeZone = cfg.timezone;
      homebrew.caskArgs.language = builtins.concatStringsSep "," cfg.shorts;
      environment.variables = {
        LANG = cfg.primary;
        LC_TIME = cfg.time;
        LANGUAGE = cfg.primary;
        LC_ALL = cfg.primary;
      };
    };

  homeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.locale;
      # The same four names the nixpkgs `i18n` module writes. This target has no `i18n` option, so
      # it writes them out.
      settings = {
        LANG = cfg.primary;
        LC_TIME = cfg.time;
        LANGUAGE = cfg.primary;
        LC_ALL = cfg.primary;
      };
    in
    {
      imports = [ declaration ];

      # `lib.mkIf` wraps the whole attribute set, never one leaf. A per-leaf `mkIf` still creates
      # the `xdg.configFile."user-dirs.dirs"` entry, and Home Manager then asserts that the entry
      # names no source.
      config = lib.mkMerge [
        {
          home.sessionVariables = settings // {
            TZ = cfg.timezone;
          };

          xdg.configFile."user-dirs.locale".source = pkgs.writeText "locale.conf" cfg.userDirs;

          xdg.configFile."locale.conf".source = pkgs.writeText "locale.conf" ''
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "${name}=${value}") settings)}
          '';
        }
        # `xdg.userDirs` writes two of these three files itself, so this target takes them over.
        (lib.mkIf config.xdg.userDirs.enable {
          xdg.configFile."user-dirs.dirs".force = true;
          xdg.configFile."locale.conf".force = true;
          xdg.configFile."user-dirs.locale".force = true;
        })
      ];
    };
in
{
  kdn.locale.nixos = nixosTarget;
  kdn.locale.darwin = darwinTarget;
  kdn.locale.homeManager = homeTarget;
}

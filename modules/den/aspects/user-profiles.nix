# The account profiles from one data file, as a den aspect.
#
# ## What it does
#
# It reads one structured data value (`data/users.data.nix`, by default) into `kdn.userProfiles`,
# and it copies each profile the host **selects** into `kdn.users` — the option that the `user`
# aspect turns into real accounts. So a host says:
#
#     kdn.userProfileData = { ... };         # supplied by importing the data file
#     kdn.userProfiles = [ "bn" ];          # which people this host has
#
# and the whole row (uid, groups, keys, password file) arrives from the data file with no
# repetition in the host file. That repetition is exactly what made a host drop a password earlier.
#
# ## Why a data file and a small aspect, not one big module
#
# `data/README.md` wants personal values in `data/`, as a value a consumer imports. The aspect here
# is the consumer: it declares the option, and a host imports the data file into it. An adopter
# deletes the data file and sets no `kdn.userProfileData`; the aspect then emits nothing.
#
# ## Password: a value is normal, a file is the override, and the two are exclusive
#
# `kdn.users.<name>.hashedPasswordFile` types as `nullOr str`. A profile carries exactly one of:
#   * `passwordHash`     — a hash **value** (the normal form). This aspect writes it to a store file
#     with `pkgs.writeText` and passes that **string** path on, so the hash lives in the data file
#     and a path lives in `kdn.users`; or
#   * `passwordHashFile` — a runtime path (a sops secret); an optional override that wins when set.
#
# The two are mutually exclusive, and the aspect asserts that a profile never sets both.
#
# The three rules this tree holds for every aspect apply: no entity argument, no aspect-level
# `enable` (the switch is including the aspect; `enable` below is a per-profile list, an option of
# this aspect, which is allowed), and no custom module argument.
{ ... }:
let
  # The record shape. The defaults let a profile name only what differs, so `root` may carry just a
  # password and `bn` may omit keys.
  profileType =
    { lib, ... }:
    {
      options = {
        uid = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
        };
        fullName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        email = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        extraGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        linger = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
        };
        primary = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        nixTrusted = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        subordinateIds = lib.mkOption {
          type = lib.types.enum [
            "auto"
            "from-uid"
            "none"
          ];
          default = "auto";
        };
        passwordHash = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "$y$j9T$yl3J5zGJ5Yq8c6fXMGxNk.$XE3X8aWpD3FeakMBD/fUmCExXMuy7B6tm7ZECmuxpF4";
          description = ''
            The password hash VALUE — the normal form. A `crypt(3)` string, e.g. from
            `mkpasswd -m yescrypt`. This is the value a data file carries.

            This aspect writes it to a store file with `pkgs.writeText` and passes that path on as
            `kdn.users.<name>.hashedPasswordFile`, so a hash stays a value in the data and a path in
            `kdn.users`. Mutually exclusive with `passwordHashFile`: set one, never both.
          '';
        };
        passwordHashFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/run/secrets/password-hash";
          description = ''
            An optional OVERRIDE: a runtime path the machine reads at activation for the hash, e.g. a
            sops secret. It wins over `passwordHash` when set.

            Typed `str` and not `path`, so no evaluation copies or reads the file — the value is a
            runtime location, not a store path. Mutually exclusive with `passwordHash`: set one,
            never both.
          '';
        };
        authorizedKeys = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        authorizedKeysFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
        };
        u2fKeysFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
        };
        gpgPublicKeysFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
        };
      };
    };

  # Resolve one profile's password to the `kdn.users.<name>.hashedPasswordFile` value. A
  # `passwordHashFile` override passes through as-is; a `passwordHash` value is written to a store
  # file and passed as a string path; neither is set yields `null`. The two are mutually exclusive
  # (the aspect asserts it), so the `if` order never has to break a tie between two set values.
  hashToFile =
    pkgs: name: p:
    if p.passwordHashFile != null then
      p.passwordHashFile
    else if p.passwordHash != null then
      "${pkgs.writeText "password-hash-${name}" (p.passwordHash + "\n")}"
    else
      null;

  # The `kdn.users` row for one profile.
  toUserRow = pkgs: name: p: {
    inherit (p) uid fullName extraGroups;
    inherit (p)
      linger
      primary
      nixTrusted
      subordinateIds
      ;
    authorizedKeys = p.authorizedKeys;
    authorizedKeysFile = p.authorizedKeysFile;
    u2fKeysFile = p.u2fKeysFile;
    gpgPublicKeysFile = p.gpgPublicKeysFile;
    hashedPasswordFile = hashToFile pkgs name p;
  };
in
{
  kdn.user-profiles.nixos =
    {
      config,
      options,
      lib,
      pkgs,
      ...
    }:
    let
      # The selected profile names that the data file actually holds. A name a host selects but the
      # data does not carry is silently dropped here — filter before `genAttrs`, so
      # `config.kdn.userProfileData.${name}` never hits a missing attribute.
      present = lib.filter (name: config.kdn.userProfileData ? ${name}) config.kdn.userProfiles;
    in
    {
      options.kdn.userProfileData = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule profileType);
        default = { };
        description = ''
          Structured account profiles (from a data file). Each key is a login name.
        '';
      };

      options.kdn.userProfiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Which profiles this host takes. Empty selects none; the aspect then emits nothing.
        '';
      };

      # Every selected, present profile becomes a `kdn.users.<name>` row, except `root`: a row set
      # there would create a normal account named `root`. `root` instead feeds
      # `kdn.profile-baseline.rootHashedPasswordFile` when that option exists.
      config.kdn.users = lib.genAttrs (lib.remove "root" present) (
        name: toUserRow pkgs name config.kdn.userProfileData.${name}
      );

      config.kdn.profile-baseline.rootHashedPasswordFile = lib.mkIf (
        builtins.elem "root" present && (options.kdn.profile-baseline ? rootHashedPasswordFile)
      ) (hashToFile pkgs "root" config.kdn.userProfileData.root);

      # `passwordHash` (a value) and `passwordHashFile` (a path override) are mutually exclusive.
      # Assert it over every profile in the data, not just the selected ones, so a dormant row is
      # wrong the same way a live one is.
      config.assertions = [
        {
          assertion = lib.all (
            name:
            let
              p = config.kdn.userProfileData.${name};
            in
            !(p.passwordHash != null && p.passwordHashFile != null)
          ) (builtins.attrNames config.kdn.userProfileData);
          message = ''
            A `kdn.userProfileData.<name>` profile may set either `passwordHash` (the hash value) or
            `passwordHashFile` (a runtime path override), never both.
          '';
        }
      ];
    };
}

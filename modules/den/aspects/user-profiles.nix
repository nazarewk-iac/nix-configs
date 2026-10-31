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
# ## Password: a written file, never an inline option
#
# `kdn.users.<name>.hashedPasswordFile` types as `nullOr str`. A profile may carry either:
#   * `passwordHashFile` — a runtime path (a sops secret); it wins; or
#   * `passwordHash`     — a hash value, which this aspect writes to a store file and passes as a
#     **string** path.
# This keeps the hash value in the data file and keeps a path string in `kdn.users`.
#
# The three rules this tree holds for every aspect apply: no entity argument, no aspect-level
# `enable` (the switch is including the aspect; `enable` below is a per-profile list, an option of
# this aspect, which is allowed), and no custom module argument.
{ ... }:
let
  # The record shape. The defaults let a profile name only what differs, so `root` may carry just a
  # password and `bn` may omit keys.
  profileType = { lib, ... }:
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
          type = lib.types.enum [ "auto" "from-uid" "none" ];
          default = "auto";
        };
        passwordHash = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        passwordHashFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
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

  # The `kdn.users` row for one profile. `passwordHash` becomes a written file path; a
  # `passwordHashFile` wins as-is.
  toUserRow =
    pkgs: name: p:
    {
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
      hashedPasswordFile =
        if p.passwordHashFile != null then
          p.passwordHashFile
        else if p.passwordHash != null then
          "${pkgs.writeText "password-hash-${name}" (p.passwordHash + "\n")}"
        else
          null;
    };
in
{
  kdn.user-profiles.nixos =
    { config, options, lib, pkgs, ... }:
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

      # Every selected profile becomes a `kdn.users.<name>` row, except `root`, which is not a
      # `kdn.users` row: a non-root profile set there would create a normal account named `root`.
      # `root` feeds `kdn.profile-baseline.rootHashedPasswordFile` when that option exists.
      config.kdn.users = lib.genAttrs (lib.remove "root" config.kdn.userProfiles) (
        name: toUserRow pkgs name config.kdn.userProfileData.${name}
      );

      config.kdn.profile-baseline.rootHashedPasswordFile = lib.mkIf
        (
          builtins.elem "root" config.kdn.userProfiles
          && (config.kdn.userProfileData ? root)
          && (options.kdn.profile-baseline ? rootHashedPasswordFile)
        )
        (
          let
            r = config.kdn.userProfileData.root;
          in
          if r.passwordHashFile != null then
            r.passwordHashFile
          else if r.passwordHash != null then
            "${pkgs.writeText "password-hash-root" (r.passwordHash + "\n")}"
          else
            null
        );
    };
}

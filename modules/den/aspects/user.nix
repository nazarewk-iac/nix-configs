# The human account shape, as a den aspect. It ports the account half of
# `modules/universal/profile/user/`.
#
# The old modules stay in place and keep working. This file is the parallel den implementation.
#
# ## The problem this aspect solves
#
# The old tree holds **one module per person**: three directories, one name each, 977 lines
# together. Each module hardcodes a login name, a numeric id, a display name, a group list and a
# password hash. An external adopter can reuse none of it.
#
# This aspect holds **no person's name**. It reads `kdn.users`, one row per account, and it writes
# the platform config for each row. The names and the values live in the consumer's own data.
#
# ## How a per-row value reaches the config, with no entity argument
#
# **An aspect takes no entity argument.** An aspect that reads `{ user, ... }` resolves to
# `{ imports = [ ]; }` across the export boundary, in silence. So a per-person value cannot arrive
# as an argument. It arrives as **an option**:
#
#   1. ../common/user-schema.nix declares `kdn.users` as an `attrsOf submodule`. The attribute name
#      is the login name.
#   2. Each target module below imports that file **by path** and reads `config.kdn.users`.
#   3. The `nixos` and `darwin` targets map every row to one `users.users.<name>` entry, so the row
#      key becomes the account name.
#   4. The `homeManager` target selects **one** row, by `config.home.username`. Home Manager always
#      declares that option, so no entity argument and no custom module argument is needed.
#
# ../disks.nix:227-256 is the precedent for step 1: `kdn.disks.users` is an `attrsOf submodule` with
# a `kdn.disks.userDefaults.*` sibling. ./ssh-access.nix:105-161 is the precedent for step 2: the
# aspect declares one option tree and its target module reads it at `:171`.
#
# ## What this aspect does NOT port
#
# The old modules mix the account with one person's whole desktop. This aspect keeps the account and
# leaves the rest to the aspect that owns it:
#
#   * A commit identity, a signing choice and a credential helper → `dev-git`, `signing`, `jj`.
#     They read `fullName` and `email` from the same rows.
#   * A browser profile set, a password store path, a screenshot directory, a chat client list, a
#     media package list → a `program-*` aspect, or the consumer's own config.
#   * `kdn.hw.yubikey.appId`, `kdn.disks.users.<name>.homeLocation`, `kdn.programs.atuin.users` and
#     `kdn.programs.fish.defaultShellUsers` → the aspect that declares each option. This aspect
#     includes none of them, so a consumer of `user` alone pulls in no hardware and no disk model.
#   * A locale override per person. `locale` declares `kdn.locale.*` inline, so a second inline
#     declaration would clash and an unconditional assignment would break a consumer that omits
#     `locale`. The consumer writes `kdn.locale.primary` next to its own user config instead.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** See the mechanism above.
# 2. **No reachable `enable` option.** Inclusion is the switch. The per-row `enable` sits inside an
#    `attrsOf submodule`, so the option-tree walk of ../../../checks/standalone.nix cannot reach it.
#    That is permitted by design — `checks/standalone.nix:207-209`.
# 3. **No custom module argument.** Each target module below takes `config` and `lib` only.
{ ... }:
let
  schema = ../common/user-schema.nix;

  # The rows that stay. A row with `enable = false` emits nothing at all.
  activeRows = lib: config: lib.filterAttrs (_: row: row.enable) config.kdn.users;

  # pam-u2f reads one line per user, in the shape `<login>:<entry1>:<entry2>:…`. `pamu2fcfg` writes
  # one `<login>:<entry>` line per registration instead. So fold the parts file: drop a comment line
  # and an empty line, group the rest by login name, keep the current login, and join its entries.
  #
  # This repeats the fold of `modules/universal/profile/user/kdn/default.nix:199-229` with the same
  # result. The read sits behind `builtins.pathExists` at the call site, because `builtins.readFile`
  # on an absent path aborts the whole evaluation.
  foldU2fParts =
    lib: username: path:
    let
      stripComments = lib.filter (line: (builtins.match "[[:space:]]*(#.*)?" line) == null);
      groupByUsername =
        input:
        builtins.mapAttrs (name: map (lib.removePrefix "${name}:")) (
          lib.groupBy (entry: lib.head (lib.splitString ":" entry)) input
        );
      toOutputLines = lib.mapAttrsToList (
        name: values: builtins.concatStringsSep ":" ([ name ] ++ values)
      );
    in
    lib.pipe path [
      builtins.readFile
      (lib.splitString "\n")
      stripComments
      groupByUsername
      (lib.filterAttrs (name: _: name == username))
      toOutputLines
      (builtins.concatStringsSep "\n")
    ];

  # Every name that at least one active row wants in `nix.settings.trusted-users`. Both OS classes
  # declare that setting, and both merge a list, so the same expression serves both.
  trustedUsers =
    lib: config: builtins.attrNames (lib.filterAttrs (_: row: row.nixTrusted) (activeRows lib config));

  nixosTarget =
    { config, lib, ... }:
    let
      rows = activeRows lib config;

      # Drop a group this machine does not declare, exactly as
      # `modules/universal/profile/user/kdn/default.nix:549` does. So one group list serves a machine
      # with Docker and a machine without it. The read forces the **names** of `users.groups` only.
      keepGroup = group: config.users.groups ? ${group};
    in
    {
      imports = [ schema ];

      config.users.users = lib.mapAttrs (
        name: row:
        {
          inherit name;
          uid = row.uid;
          # Every row is a person. So nixpkgs supplies the `users` group, the home directory and the
          # automatic subordinate range, and the `isSystemUser` exclusive-or assertion passes. A
          # service account stays the consumer's own `users.users.<name>` entry.
          isNormalUser = true;
          extraGroups = lib.filter keepGroup row.extraGroups;
          hashedPasswordFile = row.hashedPasswordFile;
          openssh.authorizedKeys.keys = row.authorizedKeys;
        }
        # `description` types as `str` with a non-null default, so a `null` cannot go in.
        // lib.optionalAttrs (row.fullName != null) { description = row.fullName; }
        # nixpkgs types `linger` as `nullOr bool`, and it asserts that a non-null value needs
        # `users.manageLingering = true`. So write the key only when the row sets it.
        // lib.optionalAttrs (row.linger != null) { linger = row.linger; }
        # `shell` defaults to `pkgs.shadow`, and a `null` there trips the `usersWithNullShells`
        # assertion of nixpkgs when `users.mutableUsers` is `false`. So write the key only when the
        # row names a shell.
        // lib.optionalAttrs (row.shell != null) { shell = row.shell; }
        // lib.optionalAttrs (row.subordinateIds == "from-uid" && row.uid != null) {
          subUidRanges = [
            {
              startUid = row.uid * 65536;
              count = 65536;
            }
          ];
          subGidRanges = [
            {
              startGid = row.uid * 65536;
              count = 65536;
            }
          ];
        }
        // lib.optionalAttrs (row.subordinateIds == "none") { autoSubUidGidRange = false; }
      ) rows;

      config.nix.settings.trusted-users = trustedUsers lib config;

      config.assertions = [
        {
          assertion = builtins.all (row: row.subordinateIds != "from-uid" || row.uid != null) (
            lib.attrValues rows
          );
          message = ''
            `kdn.users.<name>.subordinateIds = "from-uid"` needs a non-null `uid`, because the range
            starts at `uid * 65536`. Set the `uid`, or use `"auto"`.
          '';
        }
      ];
    };

  darwinTarget =
    { config, lib, ... }:
    let
      rows = activeRows lib config;

      primaries = builtins.attrNames (lib.filterAttrs (_: row: row.primary) rows);
    in
    {
      imports = [ schema ];

      # nix-darwin's own user submodule holds ten keys, and `isNormalUser`, `extraGroups`, `linger`,
      # `hashedPasswordFile` and the subordinate ranges are none of them. So this target writes the
      # five keys that exist there and it drops the rest, exactly as the old tree's
      # `ifTypes [ "nixos" "darwin" ]` guard splits them.
      #
      # It writes **no `uid`**. nix-darwin skips an account whose real uid differs from the declared
      # one, and it prints a warning at activation, so a declared id there is a silent trap. The old
      # tree writes the id under a `nixos` guard alone.
      #
      # It writes **no `users.knownUsers` entry** either. That list is what makes nix-darwin create
      # and delete a real macOS account, so it stays the consumer's own decision. Without it the
      # rows are inert data that `system.activationScripts.users` never reads.
      config.users.users = lib.mapAttrs (
        name: row:
        {
          inherit name;
          # `openssh.authorizedKeys` reaches the darwin class through nix-darwin's own
          # `modules/programs/ssh.nix`, so this key exists on both classes.
          openssh.authorizedKeys.keys = row.authorizedKeys;
          home = lib.mkDefault "/Users/${name}";
        }
        // lib.optionalAttrs (row.fullName != null) { description = row.fullName; }
        // lib.optionalAttrs (row.shell != null) { shell = row.shell; }
      ) rows;

      # `lib.mkDefault`, so a consumer's own plain value still wins. `homebrew-nix-managed` reads
      # this option for `nix-homebrew.user`, so one `primary = true` row serves Homebrew too.
      config.system.primaryUser = lib.mkIf (primaries != [ ]) (lib.mkDefault (builtins.head primaries));

      config.nix.settings.trusted-users = trustedUsers lib config;

      config.assertions = [
        {
          assertion = builtins.length primaries < 2;
          message = ''
            `system.primaryUser` holds one login name, so at most one `kdn.users.<name>` row may set
            `primary = true`. These rows set it: ${builtins.concatStringsSep ", " primaries}.
          '';
        }
      ];
    };

  homeManagerTarget =
    { config, lib, ... }:
    let
      # The one row this generation belongs to. Home Manager always declares `home.username`, so the
      # selection needs no entity argument. A generation with no matching row emits nothing.
      username = config.home.username;
      row = config.kdn.users.${username} or null;
      active = row != null && row.enable;

      hasU2f = active && row.u2fKeysFile != null && builtins.pathExists row.u2fKeysFile;
      hasGpg = active && row.gpgPublicKeysFile != null;
    in
    {
      imports = [ schema ];

      config = lib.mkMerge [
        (lib.mkIf hasU2f {
          # One folded line for this login. See `foldU2fParts` above.
          xdg.configFile."Yubico/u2f_keys".text = foldU2fParts lib username row.u2fKeysFile;
        })
        (lib.mkIf hasGpg {
          # The path goes in unchanged. The old tree copies the bytes through `pkgs.writeText`
          # first, which needs a `builtins.readFile` and therefore aborts on an absent path.
          programs.gpg.publicKeys = [
            {
              source = row.gpgPublicKeysFile;
              trust = "ultimate";
            }
          ];
        })
      ];
    };
in
{
  kdn.user.nixos = nixosTarget;
  kdn.user.darwin = darwinTarget;
  kdn.user.homeManager = homeManagerTarget;
}

# The assertion set of the `user` area: one aspect, `user`, and one shared option file,
# `modules/den/common/user-schema.nix`.
#
# It proves the answer to the one hard question of the port: **how does a per-person value reach the
# config, when an aspect takes no entity argument?** The answer is `kdn.users`, an
# `attrsOf submodule`. So every subject below writes plain data into that option and reads back what
# the platform gets.
#
# The subjects name four rows: `alpha` holds every key, `beta` holds two, `gamma` is off, and
# `delta` points every path key at an absent file. No row names a real person.
#
# Two fixtures come from `builtins.toFile`, which writes a store path **at evaluation time**. So
# `builtins.pathExists` returns true for them with no build. A `pkgs.writeText` path would not
# exist yet, and the gate would read false.
{
  lib,
  denLib,
  bareNixos,
  bareDarwinSystem,
  bareHomeConfiguration,
  ...
}:
let
  sorted = lib.sort (a: b: a < b);

  rowNames = [
    "alpha"
    "beta"
    "delta"
    "gamma"
  ];

  # The rows the aspect really emits, with every platform account (root, nobody, …) left out.
  ownRows = users: sorted (lib.filter (name: lib.elem name rowNames) (builtins.attrNames users));

  # ---------------------------------------------------------------------- the fixtures
  #
  # Two fake public keys and one empty line. The empty line must not reach the account.
  authorizedKeys = builtins.toFile "den-mvp-authorized-keys" ''
    ssh-ed25519 AAAAdenmvpfixtureone one@den-mvp

    ssh-ed25519 AAAAdenmvpfixturetwo two@den-mvp
  '';

  # `pamu2fcfg` output shape: one `<login>:<entry>` line per registration, plus a comment line.
  # The fold must keep the `dev` lines only and join their entries with a colon.
  u2fParts = builtins.toFile "den-mvp-u2f-keys-parts" ''
    # a comment line the fold drops
    dev:AAAAdenone:BBBBdenone
    dev:AAAAdentwo:BBBBdentwo
    other:AAAAdenthree:BBBBdenthree
  '';

  gpgKeys = builtins.toFile "den-mvp-gpg-pubkeys" ''
    -----BEGIN PGP PUBLIC KEY BLOCK-----
    -----END PGP PUBLIC KEY BLOCK-----
  '';

  # A store path that no build creates. `builtins.pathExists` reads false for it, and pure
  # evaluation allows the read because the path sits under the store directory.
  absentFile = "${builtins.storeDir}/den-mvp-absent-fixture";

  # ---------------------------------------------------------------------- the data
  #
  # A module function, so `shell` reads the **consumer's** own `pkgs`. A bare darwin harness and a
  # bare nixos harness hold two different platforms, and one hardcoded package would cross them.
  rowsModule =
    { pkgs, ... }:
    {
      kdn.users.alpha = {
        uid = 31000;
        fullName = "Alpha Row";
        email = "alpha@example.invalid";
        extraGroups = [
          "wheel"
          "den-mvp-absent-group"
        ];
        # `dash` names neither `bash`, `fish` nor `zsh`, so neither platform demands a matching
        # `programs.<shell>.enable`. Its name also differs from the nixpkgs default, so the read of
        # the minimal row below proves the aspect writes no shell.
        shell = pkgs.dash;
        linger = true;
        primary = true;
        nixTrusted = true;
        subordinateIds = "from-uid";
        hashedPasswordFile = "/run/secrets/den-mvp/absent-hashed-password";
        authorizedKeysFile = authorizedKeys;
        gpgPublicKeysFile = gpgKeys;
        u2fKeysFile = u2fParts;
      };

      # The minimal row. Every unset key must keep the platform default.
      kdn.users.beta = {
        uid = 31001;
        subordinateIds = "none";
      };

      # A row that is off. It must emit nothing, and its `nixTrusted` must not leak.
      kdn.users.gamma = {
        enable = false;
        uid = 31002;
        nixTrusted = true;
      };

      # Every path key points at an absent file. The aspect must still evaluate.
      kdn.users.delta = {
        uid = 31003;
        authorizedKeysFile = absentFile;
        gpgPublicKeysFile = absentFile;
        u2fKeysFile = absentFile;
        hashedPasswordFile = "/run/secrets/den-mvp/absent-too";
      };
    };

  # ---------------------------------------------------------------------- the subjects
  nixosModules = denLib.imports {
    class = "nixos";
    aspects = [ "user" ];
  };

  nixosRows = (bareNixos (nixosModules ++ [ rowsModule ])).config;

  # The adopter that includes the aspect and writes no row at all.
  nixosEmpty = (bareNixos nixosModules).config;

  # One row asks for a range from a uid it does not hold. The aspect must say so.
  nixosBadRange =
    (bareNixos (
      nixosModules
      ++ [
        { kdn.users.alpha.subordinateIds = "from-uid"; }
      ]
    )).config;

  darwinModules = denLib.imports {
    class = "darwin";
    aspects = [ "user" ];
  };

  darwinRows = (bareDarwinSystem (darwinModules ++ [ rowsModule ])).config;

  darwinEmpty = (bareDarwinSystem darwinModules).config;

  # Two rows claim the one `system.primaryUser`. The aspect must say so.
  darwinTwoPrimary =
    (bareDarwinSystem (
      darwinModules
      ++ [
        {
          kdn.users.alpha.primary = true;
          kdn.users.beta.primary = true;
        }
      ]
    )).config;

  homeModules = denLib.imports {
    class = "homeManager";
    aspects = [ "user" ];
  };

  # `bareHomeConfiguration` sets `home.username = "dev"`, so this row matches the generation.
  homeMatched =
    (bareHomeConfiguration (
      homeModules
      ++ [
        {
          kdn.users.dev.u2fKeysFile = u2fParts;
          kdn.users.dev.gpgPublicKeysFile = gpgKeys;
        }
      ]
    )).config;

  # No row carries the login name of the generation, so nothing reaches the home config.
  homeUnmatched = (bareHomeConfiguration (homeModules ++ [ rowsModule ])).config;

  # The matching row is off.
  homeDisabled =
    (bareHomeConfiguration (
      homeModules
      ++ [
        {
          kdn.users.dev.enable = false;
          kdn.users.dev.u2fKeysFile = u2fParts;
        }
      ]
    )).config;

  # The matching row points at an absent file.
  homeAbsent =
    (bareHomeConfiguration (
      homeModules
      ++ [
        { kdn.users.dev.u2fKeysFile = absentFile; }
      ]
    )).config;

  # The failing assertions of a subject whose message holds `needle`.
  failuresWith =
    needle: subject:
    builtins.length (
      lib.filter (entry: !entry.assertion && lib.hasInfix needle entry.message) subject.assertions
    );

  assertions = [
    # ------------------------------------------------------------------ the mechanism
    {
      name = "kdn.users accepts four rows and the nixos class emits the three that stay on";
      expected = [
        "alpha"
        "beta"
        "delta"
      ];
      actual = ownRows nixosRows.users.users;
    }

    {
      name = "a row with enable = false emits no account and no trusted-user entry";
      expected = {
        account = false;
        trusted = false;
      };
      actual = {
        account = nixosRows.users.users ? gamma;
        trusted = lib.elem "gamma" nixosRows.nix.settings.trusted-users;
      };
    }

    # ------------------------------------------------------------------ the nixos values
    {
      name = "the uid, the shell, the groups and the name of a full row reach the nixos config";
      expected = {
        description = "Alpha Row";
        extraGroups = [ "wheel" ];
        isNormalUser = true;
        linger = true;
        shell = "dash";
        trusted = true;
        uid = 31000;
      };
      actual = {
        description = nixosRows.users.users.alpha.description;
        # The aspect drops `den-mvp-absent-group`, because this machine declares no such group.
        extraGroups = nixosRows.users.users.alpha.extraGroups;
        isNormalUser = nixosRows.users.users.alpha.isNormalUser;
        linger = nixosRows.users.users.alpha.linger;
        shell = lib.getName nixosRows.users.users.alpha.shell;
        trusted = lib.elem "alpha" nixosRows.nix.settings.trusted-users;
        uid = nixosRows.users.users.alpha.uid;
      };
    }

    {
      name = "the authorized keys arrive from the file, with the empty line dropped";
      expected = [
        "ssh-ed25519 AAAAdenmvpfixtureone one@den-mvp"
        "ssh-ed25519 AAAAdenmvpfixturetwo two@den-mvp"
      ];
      actual = nixosRows.users.users.alpha.openssh.authorizedKeys.keys;
    }

    {
      name = "the password arrives as a runtime file path, and no hash reaches the store";
      expected = {
        hashedPassword = null;
        hashedPasswordFile = "/run/secrets/den-mvp/absent-hashed-password";
        initialHashedPassword = null;
      };
      actual = {
        hashedPassword = nixosRows.users.users.alpha.hashedPassword;
        hashedPasswordFile = nixosRows.users.users.alpha.hashedPasswordFile;
        initialHashedPassword = nixosRows.users.users.alpha.initialHashedPassword;
      };
    }

    {
      name = "the three subordinate id modes each write their own nixos result";
      expected = {
        alphaAuto = false;
        alphaSubGid = [
          {
            count = 65536;
            startGid = 2031616000;
          }
        ];
        alphaSubUid = [
          {
            count = 65536;
            startUid = 2031616000;
          }
        ];
        betaAuto = false;
        betaSubUid = [ ];
        deltaAuto = true;
        deltaSubUid = [ ];
      };
      actual = {
        # `from-uid` writes an explicit range, so nixpkgs leaves the automatic range off.
        alphaAuto = nixosRows.users.users.alpha.autoSubUidGidRange;
        alphaSubGid = nixosRows.users.users.alpha.subGidRanges;
        alphaSubUid = nixosRows.users.users.alpha.subUidRanges;
        # `none` turns the automatic range off and writes no range.
        betaAuto = nixosRows.users.users.beta.autoSubUidGidRange;
        betaSubUid = nixosRows.users.users.beta.subUidRanges;
        # `auto`, the default, writes nothing, so nixpkgs allocates the range itself.
        deltaAuto = nixosRows.users.users.delta.autoSubUidGidRange;
        deltaSubUid = nixosRows.users.users.delta.subUidRanges;
      };
    }

    {
      name = "a minimal row keeps every platform default of nixpkgs";
      expected = {
        description = "";
        extraGroups = [ ];
        group = "users";
        keys = [ ];
        linger = null;
        # `programs.bash.enable` defaults to true, so nixpkgs sets
        # `users.defaultUserShell = pkgs.bashInteractive`. The aspect writes no shell here.
        shell = "bash-interactive";
      };
      actual = {
        description = nixosRows.users.users.beta.description;
        extraGroups = nixosRows.users.users.beta.extraGroups;
        group = nixosRows.users.users.beta.group;
        keys = nixosRows.users.users.beta.openssh.authorizedKeys.keys;
        # The aspect writes no `linger`, because nixpkgs asserts a non-null value needs
        # `users.manageLingering`.
        linger = nixosRows.users.users.beta.linger;
        shell = lib.getName nixosRows.users.users.beta.shell;
      };
    }

    # ------------------------------------------------------------------ the absent file
    {
      name = "an absent key file yields an empty key list, and the aspect still evaluates";
      expected = {
        hashedPasswordFile = "/run/secrets/den-mvp/absent-too";
        keys = [ ];
        uid = 31003;
      };
      actual = {
        hashedPasswordFile = nixosRows.users.users.delta.hashedPasswordFile;
        keys = nixosRows.users.users.delta.openssh.authorizedKeys.keys;
        uid = nixosRows.users.users.delta.uid;
      };
    }

    {
      name = "three rows and an absent secret file build one nixos toplevel derivation";
      expected = true;
      actual = lib.isString nixosRows.system.build.toplevel.drvPath;
    }

    # ------------------------------------------------------------------ the empty consumer
    {
      name = "an adopter that writes no row gets an empty option and no extra account";
      expected = {
        rows = [ ];
        users = { };
      };
      actual = {
        rows = ownRows nixosEmpty.users.users;
        users = nixosEmpty.kdn.users;
      };
    }

    {
      name = "the aspect builds one nixos toplevel derivation with kdn.users left empty";
      expected = true;
      actual = lib.isString nixosEmpty.system.build.toplevel.drvPath;
    }

    # ------------------------------------------------------------------ the two guards
    {
      name = "a from-uid range with no uid raises exactly one nixos assertion";
      expected = 1;
      actual = failuresWith "subordinateIds" nixosBadRange;
    }

    {
      name = "two primary rows raise exactly one darwin assertion";
      expected = 1;
      actual = failuresWith "primary = true" darwinTwoPrimary;
    }

    # ------------------------------------------------------------------ the darwin values
    {
      name = "the darwin class emits the five keys nix-darwin declares and drops the rest";
      expected = {
        alphaDescription = "Alpha Row";
        alphaHome = "/Users/alpha";
        alphaShell = "dash";
        betaDescription = null;
        betaHome = "/Users/beta";
        betaShell = null;
        rows = [
          "alpha"
          "beta"
          "delta"
        ];
      };
      actual = {
        alphaDescription = darwinRows.users.users.alpha.description;
        alphaHome = darwinRows.users.users.alpha.home;
        alphaShell = lib.getName darwinRows.users.users.alpha.shell;
        betaDescription = darwinRows.users.users.beta.description;
        betaHome = darwinRows.users.users.beta.home;
        betaShell = darwinRows.users.users.beta.shell;
        rows = ownRows darwinRows.users.users;
      };
    }

    {
      name = "the darwin class writes no uid, so nix-darwin never skips a real account";
      expected = false;
      # nix-darwin types `uid` with no default. So an unset value throws, and `tryEval` catches it.
      # A written value would make this read succeed.
      actual = (builtins.tryEval darwinRows.users.users.alpha.uid).success;
    }

    {
      name = "the darwin class leaves knownUsers alone and lets a consumer keep primaryUser";
      expected = {
        knownUsers = [ ];
        primaryUser = "den";
        trusted = true;
      };
      actual = {
        # nix-darwin's own nix module puts every `nixbld` account in `users.knownUsers`, so an
        # exact-list probe measures nix-darwin and not the aspect. This membership probe keeps the
        # real intent: no row name reaches the list, so nix-darwin creates and deletes no account of
        # this aspect and the rows stay inert.
        knownUsers = lib.intersectLists (builtins.attrNames darwinRows.kdn.users) darwinRows.users.knownUsers;
        # The harness writes `den` at the plain priority, and the aspect writes `lib.mkDefault`. So
        # the consumer wins and no priority clash stops the evaluation.
        primaryUser = darwinRows.system.primaryUser;
        trusted = lib.elem "alpha" darwinRows.nix.settings.trusted-users;
      };
    }

    {
      name = "the authorized keys of a row reach the nix-darwin etc file";
      expected = {
        alpha = true;
        # An absent file yields no key, so nix-darwin writes no file for that row.
        delta = false;
        gamma = false;
      };
      actual = {
        alpha = darwinRows.environment.etc ? "ssh/nix_authorized_keys.d/alpha";
        delta = darwinRows.environment.etc ? "ssh/nix_authorized_keys.d/delta";
        gamma = darwinRows.environment.etc ? "ssh/nix_authorized_keys.d/gamma";
      };
    }

    {
      name = "the darwin class emits no account when kdn.users stays empty";
      expected = {
        rows = [ ];
        users = { };
      };
      actual = {
        rows = ownRows darwinEmpty.users.users;
        users = darwinEmpty.kdn.users;
      };
    }

    {
      name = "three rows build one darwin toplevel derivation";
      expected = true;
      actual = lib.isString darwinRows.system.build.toplevel.drvPath;
    }

    # ------------------------------------------------------------------ the homeManager values
    {
      name = "the home class folds the u2f parts file into one line for the current login";
      expected = "dev:AAAAdenone:BBBBdenone:AAAAdentwo:BBBBdentwo";
      actual = homeMatched.xdg.configFile."Yubico/u2f_keys".text;
    }

    {
      name = "the home class trusts the gpg key file by path, with no readFile";
      expected = {
        count = 1;
        source = gpgKeys;
        trust = 5;
      };
      actual = {
        count = builtins.length homeMatched.programs.gpg.publicKeys;
        source = toString (builtins.head homeMatched.programs.gpg.publicKeys).source;
        # Home Manager maps the `ultimate` name to the number 5 through an `apply`.
        trust = (builtins.head homeMatched.programs.gpg.publicKeys).trust;
      };
    }

    {
      name = "a home generation emits nothing when no row matches, the row is off, or the file is absent";
      expected = {
        absentGpg = [ ];
        absentU2f = false;
        disabledU2f = false;
        unmatchedGpg = [ ];
        unmatchedU2f = false;
      };
      actual = {
        absentGpg = homeAbsent.programs.gpg.publicKeys;
        absentU2f = homeAbsent.xdg.configFile ? "Yubico/u2f_keys";
        disabledU2f = homeDisabled.xdg.configFile ? "Yubico/u2f_keys";
        # `rowsModule` names alpha, beta, gamma and delta, and the generation belongs to `dev`.
        unmatchedGpg = homeUnmatched.programs.gpg.publicKeys;
        unmatchedU2f = homeUnmatched.xdg.configFile ? "Yubico/u2f_keys";
      };
    }

    {
      name = "a matching row builds one home activation derivation";
      expected = true;
      actual = lib.isString homeMatched.home.activationPackage.drvPath;
    }
  ];

  # ------------------------------------------------------------------ the coverage row
  #
  # `../tests.nix` merges this set into the table that `den-eval-coverage` reads. So this batch adds
  # its own row and needs no edit to a shared file.
  instantiatedBy = {
    user = "den-eval-user (bare nixos, bare darwin and bare home, four rows and an empty option)";
  };
in
{
  inherit assertions instantiatedBy;
}

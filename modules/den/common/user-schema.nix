# One declaration of `kdn.users`, shared by every aspect that needs a person's account facts.
#
# ## What the option means
#
# `kdn.users` holds one row per human account. The attribute name **is** the login name, and the row
# holds the facts an account needs: a numeric id, a full name, a group list, a public key list and a
# password **file**. ../aspects/user.nix reads the rows and writes `users.users.<name>`.
#
# ## Why a separate file, and why an import by path
#
# The module system rejects two inline declarations of one option. It does dedupe an import **by
# path**. So every aspect that needs a row writes one line in its target module:
#
#     imports = [ ../common/user-schema.nix ];
#
# A later aspect reads the same rows with the same one line — `dev-git` for the commit identity,
# `signing` for the signing key. The shape copies ./host-name.nix and ./source-repo.nix.
#
# ## The per-row `enable` is deliberate
#
# ../../../checks/standalone.nix walks the option tree and stops at an option, so an `enable` inside
# an `attrsOf submodule` is out of reach — see `checks/standalone.nix:207-209` and `:242-256`. A row
# is data, not a feature switch, so `enable = false` removes one person and leaves the aspect on.
#
# ## No password hash, ever
#
# A row carries `hashedPasswordFile`, a **string** path that the machine reads at activation time. It
# carries no hash, and it declares no `hashedPassword` key at all. The old tree inlines a hash in a
# tracked file, and this repository has a public origin. nixpkgs types
# `users.users.<name>.hashedPasswordFile` as `nullOr str`, so no evaluation reads the file. An absent
# file therefore cannot abort an evaluation.
#
# An adopter with no secret system leaves the key `null` and writes
# `users.users.<name>.hashedPassword` in its own config. That option is nixpkgs' own, so it needs
# nothing from this tree.
#
# ## Three keys hold a path this tree reads at evaluation time
#
# `authorizedKeysFile`, `gpgPublicKeysFile` and `u2fKeysFile` name a **public** key file. Only the
# first one gets a `builtins.readFile`, and it sits behind `builtins.pathExists`, because
# `builtins.readFile` on an absent path aborts the whole evaluation and `builtins.tryEval` does not
# catch that abort.
#
# This file declares one option and sets no config, so it is safe in every class. It takes `lib`
# only, so it needs no `specialArgs` from the consumer.
{ lib, ... }:
{
  options.kdn.users = lib.mkOption {
    default = { };
    example = lib.literalExpression ''
      {
        adopter.uid = 31000;
        adopter.fullName = "A Dopter";
        adopter.extraGroups = [ "wheel" ];
        adopter.primary = true;
        adopter.nixTrusted = true;
      }
    '';
    description = ''
      One row per human account. The attribute name is the login name.

      Every value is the consumer's own. This file names no person, no numeric id, no key and no
      password.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }:
        {
          options.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            example = false;
            description = ''
              Keep this row. Set it to `false` to drop the account and emit nothing for it.

              This is a per-row switch and not an aspect switch. Inclusion of the aspect stays the
              only switch for the aspect itself.
            '';
          };

          options.uid = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            example = 31000;
            description = ''
              The numeric user id. `null` lets the platform pick one.

              The darwin target never writes this key. nix-darwin skips an account whose real uid
              differs from the declared one, so a wrong value there is silent.
            '';
          };

          options.fullName = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "A Dopter";
            description = ''
              The person's display name. It maps to `users.users.<name>.description` on both OS
              classes. `null` keeps the platform default.
            '';
          };

          options.email = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "adopter@example.invalid";
            description = ''
              The person's email address. The `user` aspect emits nothing from it.

              It is here so that a commit identity and a signing key read one row. A later aspect
              imports this file and reads the value.
            '';
          };

          options.extraGroups = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            example = [
              "wheel"
              "video"
            ];
            description = ''
              Supplementary groups, for `users.users.<name>.extraGroups`.

              The `user` aspect drops a name that `config.users.groups` does not hold, exactly as the
              old tree does. So one list serves a machine with Docker and a machine without it.

              nix-darwin declares no such option, so the darwin target ignores this key.
            '';
          };

          options.authorizedKeys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default =
              if config.authorizedKeysFile == null || !builtins.pathExists config.authorizedKeysFile then
                [ ]
              else
                lib.filter (line: line != "") (lib.splitString "\n" (builtins.readFile config.authorizedKeysFile));
            defaultText = lib.literalExpression "the lines of `authorizedKeysFile`, or `[ ]`";
            description = ''
              Public SSH keys of the account, one string per key. They reach
              `users.users.<name>.openssh.authorizedKeys.keys` on both OS classes.

              The default reads `authorizedKeysFile` and drops an empty line. Use
              `openssh.authorizedKeys.keys` and never `.keyFiles`: both nixpkgs and nix-darwin read a
              `keyFiles` entry with `builtins.readFile` at evaluation time, so an absent file there
              aborts the evaluation.
            '';
          };

          options.authorizedKeysFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            example = lib.literalExpression "./authorized_keys";
            description = ''
              A file that seeds `authorizedKeys`, one key per line. A `#` comment is not supported,
              because the file goes to `openssh.authorizedKeys.keys` unchanged.

              An absent path yields the empty list. The read sits behind `builtins.pathExists`.
            '';
          };

          options.hashedPasswordFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "/run/secrets/users/adopter/hashed-password";
            description = ''
              The path of a file that holds one line: the salted password hash.

              The type is `str` and not `path`, so the value stays a runtime path and no evaluation
              copies the file into the store. The machine reads the file at every activation, so a
              secret manager may create it after the build.

              An adopter with no secret manager leaves this `null` and writes
              `users.users.<name>.hashedPassword` in its own config instead.

              nix-darwin declares no password option at all, so the darwin target ignores this key.
            '';
          };

          options.gpgPublicKeysFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            example = lib.literalExpression "./gpg-pubkeys.txt";
            description = ''
              An exported GPG public keyring to trust at the `ultimate` level. It reaches
              `programs.gpg.publicKeys` in the Home Manager class.
            '';
          };

          options.u2fKeysFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            example = lib.literalExpression "./u2f_keys.parts";
            description = ''
              The output of `pamu2fcfg`, one `<login>:<entry>` line per registration. A `#` comment
              line and an empty line are both dropped.

              pam-u2f wants one line per user, with every entry on that line. The Home Manager class
              folds the file into that shape and writes
              `$XDG_CONFIG_HOME/Yubico/u2f_keys`. It keeps the lines of the current
              `home.username` only, so one shared file may serve several people.

              An absent path emits no file. The read sits behind `builtins.pathExists`.
            '';
          };

          options.shell = lib.mkOption {
            type = lib.types.nullOr (lib.types.either lib.types.shellPackage lib.types.path);
            default = null;
            example = lib.literalExpression "pkgs.bashInteractive";
            description = ''
              The login shell. `null` keeps each platform's own default, so the `user` aspect writes
              the key only when a row names a shell.

              Both nixpkgs and nix-darwin assert that `programs.<shell>.enable` is `true` for
              `fish`, `zsh` and `xonsh`. So a row that names one of those needs the matching
              `programs.*.enable` line in the consumer's own config.
            '';
          };

          options.linger = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            example = true;
            description = ''
              Keep the user's systemd instance alive with no login session. It maps to
              `users.users.<name>.linger`, a NixOS-only option.

              `null` leaves the choice to the machine, and `loginctl enable-linger` still works.
              nixpkgs asserts that a non-null value needs `users.manageLingering = true`, so the
              `user` aspect writes the key only when the row sets it.
            '';
          };

          options.primary = lib.mkOption {
            type = lib.types.bool;
            default = false;
            example = true;
            description = ''
              This person runs `darwin-rebuild`. The darwin target writes
              `system.primaryUser = lib.mkDefault "<name>"`.

              `modules/den/aspects/homebrew-nix-managed.nix` reads `system.primaryUser` for
              `nix-homebrew.user`, so one `primary = true` row serves Homebrew too. At most one row
              may set it; the aspect asserts that.

              The NixOS class has no such concept and ignores this key.
            '';
          };

          options.nixTrusted = lib.mkOption {
            type = lib.types.bool;
            default = false;
            example = true;
            description = ''
              Add the login name to `nix.settings.trusted-users`. A trusted user may set any Nix
              setting and may add any binary cache, so grant it to a machine owner only.
            '';
          };

          options.subordinateIds = lib.mkOption {
            type = lib.types.enum [
              "auto"
              "from-uid"
              "none"
            ];
            default = "auto";
            example = "from-uid";
            description = ''
              How this account gets its subordinate uid and gid range, which a rootless container
              needs.

              * `auto` writes nothing. nixpkgs then sets `autoSubUidGidRange` for a normal user with
                no explicit range, and it allocates the range itself.
              * `from-uid` writes an explicit range that starts at `uid * 65536` and holds 65536
                ids. It reproduces the old tree, so an existing container keeps its stored mapping.
                It needs a non-null `uid`.
              * `none` sets `autoSubUidGidRange = false` and writes no range, so the account runs no
                rootless container.

              NixOS-only. nix-darwin has no subordinate id model.
            '';
          };
        }
      )
    );
  };
}

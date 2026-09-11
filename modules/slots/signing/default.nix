# SSH commit signing: a verifiable `allowed_signers` file, plus a switch to a plain key.
#
# The slot owns three things.
#
#   1. An `allowed_signers` file. The slot generates it from a list of entries, then wires the
#      one file into both tools: `gpg.ssh.allowedSignersFile` for git, and
#      `signing.backends.ssh.allowed-signers` for jj. Without that file each tool signs but
#      verifies nothing, and `jj log -T 'signature.status()'` reports `SIGNED bad`.
#
#   2. An alternate configuration pair in the store: one git file and one jj file. Both select
#      plain `ssh-keygen` as the signer, and a plain private key file as the signing key. The jj
#      file also sets `signing.behavior = "force"`, because `"own"` compares the commit author
#      e-mail against `user.email` and signs nothing when the two differ.
#
#   3. `kdn-signing`, a script on PATH. It prints the shell lines that select a route. A child
#      process cannot change the environment of its parent, so the caller runs the lines:
#      `eval "$(kdn-signing plain)"`.
#
# Why an environment-variable switch, and not a second home-manager generation: a route change
# must take effect in one shell, at once, with no activation and no sudo. `GIT_CONFIG_GLOBAL`,
# `JJ_CONFIG` and `GIT_SSH_COMMAND` all do that. `GIT_CONFIG_GLOBAL` replaces the whole global
# file, so the generated git file starts with an `include.path` of the real global file, and it
# repeats `user.name` and `user.email` after the include.
#
# `GIT_SSH_COMMAND` carries `-o IdentityAgent=$SSH_AUTH_SOCK`. A command-line `-o` beats every
# `ssh_config` file, so it is the only way past an `IdentityAgent` directive in a `Host *` block.
# `SSH_AUTH_SOCK` alone cannot do it: `ssh` keeps the first value it reads for a directive.
#
# The slot holds no principal and no key. The consumer passes every value.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.signing;

  signerType = lib.types.submodule {
    options.principals = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Principals the key signs for. An e-mail address is the usual principal.";
    };
    options.key = lib.mkOption {
      type = lib.types.str;
      description = "The public key, in `ssh-<type> <base64>` form. A trailing comment is allowed.";
    };
    options.namespaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Limit the entry to these namespaces. Both git and jj sign in the `git` namespace. An
        empty list writes no `namespaces=` option, so the entry serves every namespace.
      '';
    };
  };
in
{
  options.kdn.signing = {
    enable = lib.mkEnableOption "verifiable SSH commit signing, and a plain-key alternate route";

    allowedSigners = lib.mkOption {
      type = lib.types.listOf signerType;
      default = [ ];
      example = [
        {
          principals = [ "someone@example.invalid" ];
          key = "ssh-ed25519 AAAAC3Nz... hardware key";
        }
      ];
      description = ''
        Entries of the generated `allowed_signers` file. The slot wires the file into git and
        into jj. An empty list writes no file and changes neither tool.

        Add one entry for each key that signs your own commits. A second key becomes valid with
        no other change.
      '';
    };

    plain.keyFile = lib.mkOption {
      type = lib.types.str;
      default = "~/.ssh/id_ed25519_plain_signing";
      example = "~/.ssh/id_ed25519_signing";
      description = ''
        Private key file of the plain route. The module never creates this file. Create it by
        hand:

        ```
        ssh-keygen -t ed25519 -C '<principal> plain signing key' -f <this path>
        ```

        A leading `~/` expands against the home directory of each home-manager user. The
        expansion matters: jj reads a relative `signing.key` as inline key material.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        expandHome =
          path:
          if lib.hasPrefix "~/" path then
            "${config.home.homeDirectory}/${lib.removePrefix "~/" path}"
          else
            path;

        plainKeyFile = expandHome cfg.plain.keyFile;
        sshKeygen = lib.getExe' pkgs.openssh "ssh-keygen";

        signerLine =
          entry:
          lib.concatStringsSep " " (
            [ (lib.concatStringsSep "," entry.principals) ]
            ++ lib.optional (
              entry.namespaces != [ ]
            ) ''namespaces="${lib.concatStringsSep "," entry.namespaces}"''
            ++ [ entry.key ]
          );

        allowedSignersFile = pkgs.writeText "allowed_signers" (
          lib.concatMapStringsSep "\n" signerLine cfg.allowedSigners + "\n"
        );

        # The real global files. The alternate files build on top of them, so no personal value
        # is repeated more than once.
        gitBaseConfig = "${config.xdg.configHome}/git/config";
        jjBaseConfig = "${config.xdg.configHome}/jj/config.toml";

        gitPlainConfig = pkgs.writeText "git-signing-plain.config" ''
          # Alternate git config: sign with a plain ssh-keygen key.
          # `GIT_CONFIG_GLOBAL` replaces the whole global file, so this file includes the real
          # global file first. The keys after the include win, because git keeps the last value.
          [include]
            path = ${gitBaseConfig}
          [user]
            name = ${config.programs.git.settings.user.name or ""}
            email = ${config.programs.git.settings.user.email or ""}
            signingKey = ${plainKeyFile}
          [commit]
            gpgSign = true
          [tag]
            gpgSign = true
          [gpg]
            format = ssh
          [gpg "ssh"]
            program = ${sshKeygen}
            allowedSignersFile = ${allowedSignersFile}
        '';

        # `JJ_CONFIG` takes a list of paths, separated by the platform path separator, and a
        # later path wins. So this file holds the override only, and the script prepends the
        # real user config.
        jjPlainConfig = (pkgs.formats.toml { }).generate "jj-signing-plain.toml" {
          signing.behavior = "force";
          signing.backend = "ssh";
          signing.key = plainKeyFile;
          signing.backends.ssh.program = sshKeygen;
          signing.backends.ssh.allowed-signers = "${allowedSignersFile}";
        };

        kdnSigning = pkgs.writeShellApplication {
          name = "kdn-signing";
          text = ''
            # Defaults from the nix build. An environment value wins, which keeps the script
            # testable outside an activated configuration.
            : "''${KDN_SIGNING_GIT_PLAIN:=${gitPlainConfig}}"
            : "''${KDN_SIGNING_JJ_PLAIN:=${jjPlainConfig}}"
            : "''${KDN_SIGNING_JJ_BASE:=${jjBaseConfig}}"
            : "''${KDN_SIGNING_ALLOWED_SIGNERS:=${allowedSignersFile}}"
            : "''${KDN_SIGNING_PLAIN_KEY:=${plainKeyFile}}"
          ''
          + builtins.readFile ../../../hack/kdn-signing.sh;
        };
      in
      # Skip a user without git, for example root. The `home` target serves every
      # home-manager user.
      lib.mkIf config.programs.git.enable (
        lib.mkMerge [
          { home.packages = [ kdnSigning ]; }
          (lib.mkIf (cfg.allowedSigners != [ ]) {
            programs.git.settings.gpg.ssh.allowedSignersFile = "${allowedSignersFile}";
          })
          (lib.mkIf (cfg.allowedSigners != [ ] && config.programs.jujutsu.enable) {
            programs.jujutsu.settings.signing.backends.ssh.allowed-signers = "${allowedSignersFile}";
          })
        ]
      );
  };
}

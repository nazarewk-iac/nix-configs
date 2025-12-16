{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.kdn.profile.user.kdn;

  nc.rel = "Nextcloud/drag0nius@nc.nazarewk.pw";
  nc.abs = "${config.home.homeDirectory}/${nc.rel}";
in {
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.programs.ssh-client.enable = true;
        home.file.".ssh/config.d/kdn.config".source =
          config.lib.file.mkOutOfStoreSymlink "/run/configs/networking/ssh_config/kdn";

        # pam-u2f expects a single line of configuration per user in format `username:entry1:entry2:entry3:...`
        # `pamu2fcfg` generates lines of format `username:entry`
        # For ease of use you can append those pamu2fcfg to ./yubico/u2f_keys.parts directly,
        #  then below code will take care of stripping comments and folding it into a single line per user
        xdg.configFile."Yubico/u2f_keys".text = let
          stripComments = lib.filter (
            line: (builtins.match "\w*" line) == null && (builtins.match "\w*#.*" line) == null
          );
          groupByUsername = input:
            builtins.mapAttrs (name: map (lib.removePrefix "${name}:")) (
              lib.groupBy (e: lib.head (lib.strings.splitString ":" e)) input
            );
          toOutputLines = lib.attrsets.mapAttrsToList (
            name: values: (builtins.concatStringsSep ":" (
              lib.concatLists [
                [name]
                values
              ]
            ))
          );

          foldParts = path:
            lib.trivial.pipe path [
              builtins.readFile
              (lib.strings.splitString "\n")
              stripComments
              groupByUsername
              (lib.attrsets.filterAttrs (n: v: n == config.home.username))
              toOutputLines
              (builtins.concatStringsSep "\n")
            ];
        in
          foldParts ./yubico/u2f_keys.parts;
      }
      {
        # GPG
        programs.gpg.publicKeys = [
          {
            source = cfg.gpg.publicKeys;
            trust = "ultimate";
          }
        ];
        home.activation = {
          linkPasswordStore = lib.hm.dag.entryBetween ["linkGeneration"] ["writeBoundary"] ''
            $DRY_RUN_CMD ln -sfT "${nc.rel}/important/password-store" "$HOME/.password-store"
          '';
        };
        programs.password-store.enable = true;
        programs.password-store.settings = {
          PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
          PASSWORD_STORE_CLIP_TIME = "10";
        };
      }
      {
        programs.gh.enable = false;
        programs.gh.gitCredentialHelper.enable = false;
        # programs.git.signing.key = "CDDFE1610327F6F7A693125698C23F71A188991B";
        programs.git.signing.key = null;
        programs.git.signing.signByDefault = true;
        programs.git.ignores = [(builtins.readFile ./.gitignore.tpl)];
        programs.git.attributes = [(builtins.readFile ./.gitattributes)];
        # to authenticate hub: ln -s ~/.config/gh/hosts.yml ~/.config/hub
        programs.git.settings = {
          user.name = "Krzysztof Nazarewski";
          user.email = "gpg@kdn.im";
          credential.helper = let
            wrapped = pkgs.writeShellApplication {
              name = "git-credential-keyring-wrapped";
              runtimeInputs = [pkgs.kdn.git-credential-keyring];
              text = ''
                export PYTHON_KEYRING_BACKEND="keyring_pass.PasswordStoreBackend"
                export KEYRING_PROPERTY_PASS_BINARY="${pkgs.pass}/bin/pass"
                export GIT_CREDENTIAL_KEYRING_IGNORE_DELETIONS=1
                git-credential-keyring "$@"
              '';
            };
          in "${wrapped}/bin/git-credential-keyring-wrapped";

          credential."https://github.com".username = "nazarewk";
          url."https://github.com/".insteadOf = "git@github.com:";
          credential."https://gist.github.com".username = "nazarewk";
          url."https://gist.github.com/".insteadOf = "git@gist.github.com:";
        };
        programs.jujutsu.settings = {
          user.name = "Krzysztof Nazarewski";
          user.email = "gpg@kdn.im";
          signing.behavior = "own";
          signing.backend = "gpg";
        };
      }
    ]
  );
}

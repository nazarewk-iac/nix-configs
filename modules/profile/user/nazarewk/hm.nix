{ config, pkgs, lib, ... }@arguments:
let
  cfg = config.kdn.profile.user.nazarewk;
in
{
  options.kdn.profile.user.nazarewk = {
    enable = lib.mkEnableOption "enable nazarewk user profile";
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.stateVersion = "22.11";

      programs.gh.enable = false;
      programs.gh.enableGitCredentialHelper = false;
      programs.git.enable = true;
      # programs.git.signing.key = "CDDFE1610327F6F7A693125698C23F71A188991B";
      programs.git.signing.key = null;
      programs.git.signing.signByDefault = true;
      programs.git.userName = "Krzysztof Nazarewski";
      programs.git.userEmail = "3494992+nazarewk@users.noreply.github.com";
      programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
      programs.git.attributes = [ (builtins.readFile ./.gitattributes) ];
      # to authenticate hub: ln -s ~/.config/gh/hosts.yml ~/.config/hub
      programs.git.extraConfig = {
        # use it separately because `gh` cli wants to write to ~/.config/gh/config.yml
        credential."https://github.com".helper = "${pkgs.gh}/bin/gh auth git-credential";
        url."https://github.com/".insteadOf = "git@github.com:";
      };

      programs.ssh.enable = true;
      programs.zsh.enable = true;
      programs.ssh.extraConfig = ''
        Host *
          Include ~/.ssh/config.local
      '';

      home.packages = with pkgs; [
        pass
      ];

      kdn.development.git.enable = true;
    }
    (lib.mkIf config.kdn.headless.enableGUI {
      services.flameshot.settings.General.savePath = "${config.home.homeDirectory}/Downloads/screenshots";
      xdg.configFile."gsimplecal/config".source = ./gsimplecal/config;

      systemd.user.services.nextcloud-client.Unit.After = [ "tray.target" ];
      systemd.user.services.nextcloud-client.Unit.Requires = [ "tray.target" ];
      services.nextcloud-client = {
        enable = true;
        startInBackground = true;
      };

      # pam-u2f expects a single line of configuration per user in format `username:entry1:entry2:entry3:...`
      # `pamu2fcfg` generates lines of format `username:entry`
      # For ease of use you can append those pamu2fcfg to ./yubico/u2f_keys.parts directly,
      #  then below code will take care of stripping comments and folding it into a single line per user
      xdg.configFile."Yubico/u2f_keys".text =
        let
          stripComments = lib.filter (line: (builtins.match "\w*" line) != [ ] && (builtins.match "\w*#.*" line) != [ ]);
          groupByUsername = input: builtins.mapAttrs (name: map (lib.removePrefix "${name}:")) (lib.groupBy (e: lib.head (lib.splitString ":" e)) input);
          toOutputLines = lib.mapAttrsToList (name: values: (builtins.concatStringsSep ":" (lib.concatLists [ [ name ] values ])));

          foldParts = path: lib.pipe path [
            builtins.readFile
            (lib.splitString "\n")
            stripComments
            groupByUsername
            toOutputLines
            (builtins.concatStringsSep "\n")
          ];
        in
        foldParts ./yubico/u2f_keys.parts;

      home.packages = with pkgs; [
        (pkgs.writeShellApplication {
          name = ",drag0nius.kdbx";
          runtimeInputs = [ pkgs.pass pkgs.keepass ];
          text = ''
            cmd_start () {
                local db_path="$HOME/Nextcloud/drag0nius@nc.nazarewk.pw/Dropbox import/Apps/KeeAnywhere/drag0nius.kdbx"
                pass KeePass/drag0nius.kdbx | keepass "$db_path" -pw-stdin
            }

            "cmd_''${1:-start}" "''${@:2}"
          '';
        })
      ];
    })
  ]);
}

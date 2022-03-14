{ config, pkgs, lib, ... }:

let
  keepassWithPlugins = pkgs.keepass.override {
    plugins = with pkgs; [
      keepass-keeagent
      keepass-keepassrpc
      keepass-keetraytotp
      keepass-charactercopy
      keepass-qrcodeview
    ];
  };
in {
  xdg.configFile."sway/config".source = ./sway/config;
  xdg.configFile."swayr/config.toml".source = ./swayr/config.toml;
  xdg.configFile."waybar/config".source = ./waybar/config;
  xdg.configFile."waybar/style.css".source = ./waybar/style.css;

  # pam-u2f expects a single line of configuration per user in format `username:entry1:entry2:entry3:...`
  # `pamu2fcfg` generates lines of format `username:entry`
  # For ease of use you can append those pamu2fcfg to ./yubico/u2f_keys.parts directly,
  #  then below code will take care of stripping comments and folding it into a single line per user
  xdg.configFile."Yubico/u2f_keys".text = let
    stripComments = lib.filter (line: (builtins.match "\w*" line) != [] && (builtins.match "\w*#.*" line) != []);
    groupByUsername = input: builtins.mapAttrs (name: map (lib.removePrefix "${name}:")) (builtins.groupBy (e: lib.head (lib.splitString ":" e)) input);
    toOutputLines = lib.mapAttrsToList (name: values: (builtins.concatStringsSep ":" (lib.concatLists [[name] values])));

    foldParts = path: lib.pipe path [
      builtins.readFile
      (lib.splitString "\n")
      stripComments
      groupByUsername
      toOutputLines
      (builtins.concatStringsSep "\n")
    ];
   in foldParts ./yubico/u2f_keys.parts;

  programs.gh.enable = false;
  programs.gh.enableGitCredentialHelper = false;
  programs.git.enable = true;
  programs.git.signing.key = "916D8B67241892AE";
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
  programs.starship.enable = true;

  home.packages = with pkgs; [
    # # launch-waybar doesn't worth with nix changes
    # (pkgs.writeScriptBin "launch-waybar" ''
    #   #! ${pkgs.bash}/bin/bash
    #   # based on https://github.com/Alexays/Waybar/issues/961#issuecomment-753533975
    #   CONFIG_FILES=(
    #     "$HOME/.config/waybar/config"
    #     "$HOME/.config/waybar/style.css"
    #   )
    #   pid=
    #   trap '[ -z "$pid" ] || kill $pid' EXIT

    #   while true; do
    #       ${pkgs.waybar}/bin/waybar "$@" &
    #       pid=$!
    #       ${pkgs.inotify-tools}/bin/inotifywait -e create,modify $CONFIG_FILES
    #       kill $pid
    #       pid=
    #   done
    # '')
    keepassWithPlugins
    pass
    (pkgs.writeShellApplication {
      name = ",drag0nius.kdbx";
      runtimeInputs = [ pkgs.pass keepassWithPlugins ];
      text = ''
        cmd_start () {
            local db_path="$HOME/Nextcloud/drag0nius@nc.nazarewk.pw/Dropbox import/Apps/KeeAnywhere/drag0nius.kdbx"
            pass KeePass/drag0nius.kdbx | keepass "$db_path" -pw-stdin
        }

        "cmd_''${1:-start}" "''${@:2}"
      '';
    })
  ];

  nazarewk.development.git.enable = true;

  home.sessionVariables.AWS_VAULT_BACKEND = "secret-service";
}

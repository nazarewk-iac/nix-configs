{ config, pkgs, ... }:

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

  home.file.".yubico".source = ./yubico;
  home.file.".yubico".recursive = true;

  programs.git.enable = true;
  programs.git.signing.key = "916D8B67241892AE";
  programs.git.signing.signByDefault = true;
  programs.git.userName = "Krzysztof Nazarewski";
  programs.git.userEmail = "3494992+nazarewk@users.noreply.github.com";
  programs.git.ignores = [ (builtins.readFile ./.gitignore) ];
  programs.git.attributes = [ (builtins.readFile ./.gitattributes) ];

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

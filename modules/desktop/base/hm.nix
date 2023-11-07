{ nixosConfig, config, pkgs, lib, ... }:
let
  cfg = config.kdn.desktop.base;
  ydotool-paste = pkgs.writeShellApplication {
    name = "ydotool-paste";
    runtimeInputs = with pkgs; [ ydotool wl-clipboard ];
    text = ''
      sleep "''${1:-0.5}"
      wl-paste --no-newline | ydotool type --file=-
    '';
  };
in
{
  options.kdn.desktop.base = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = nixosConfig.kdn.desktop.base.enable;
    };
  };
  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) {
    xdg.configFile."wofi/config".source = ./wofi/config;

    home.packages = with pkgs; [
      ydotool-paste

      qalculate-qt
      libqalculate
    ];

    home.sessionPath = [ "$HOME/.local/bin" ];

    programs.foot = {
      enable = true;

      server.enable = false;
      settings.main = {
        font = "JetBrainsMono Nerd Font Mono:style=Regular:size=12";
        dpi-aware = "no";
      };
      settings.scrollback.lines = 100000;
    };
  };
}

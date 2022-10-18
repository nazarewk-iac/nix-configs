{ config, pkgs, lib, ... }:
let
  swaylock = "${pkgs.swaylock}/bin/swaylock";
  lock = "${swaylock} -f";
  swayPkg = config.wayland.windowManager.sway.package;
  swaymsg = "${swayPkg}/bin/swaymsg";

  key = {
    super = "Mod4";
    lalt = "Mod1";
    ralt = "Mod5";
    ctrl = "Control";
    shift = "Shift";
  };
in
{
  config = lib.mkMerge [
    (lib.mkIf config.kdn.headless.enableGUI {
      wayland.windowManager.sway = {
        enable = true;
        config.keybindings = { };
        config.modes = { };
        config.bars = [ ];
        extraConfig = builtins.readFile ./sway/config;
      };

      xdg.configFile."swayr/config.toml".source = ./swayr/config.toml;
      xdg.configFile."waybar/config".source = ./waybar/config;
      xdg.configFile."waybar/style.css".source = ./waybar/style.css;
      xdg.configFile."wofi/config".source = ./wofi/config;

      programs.foot = {
        enable = true;
        server.enable = false;
        settings = {
          main = {
            font = "JetBrainsMono Nerd Font Mono:style=Regular:size=10";
            dpi-aware = "yes";
          };
        };
      };

      wayland.windowManager.sway.config.keybindings."${key.super}+L" = "exec ${lock}";
      services.swayidle = {
        enable = true;
        events = [
          { event = "before-sleep"; command = lock; }
        ];
        timeouts = [
          {
            timeout = 300;
            command = lock;
          }
          {
            timeout = 240;
            command = ''${swaymsg} "output * dpms off"'';
            resumeCommand = ''${swaymsg} "output * dpms on"'';
          }
        ];
      };

      programs.swaylock.settings = {
        color = "000000";
        show-failed-attempts = true;
      };
    })
  ];
}

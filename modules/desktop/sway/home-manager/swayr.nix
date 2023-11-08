{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.desktop.sway;

  mod = import ./_modifiers.nix;
  systemd-cat = name: "${pkgs.systemd}/bin/systemd-cat --identifier=${config.home.username}-${name}";
  exec = cmd: "exec '${cmd}'";

  swayr = cmd: "${systemd-cat "swayr"} env RUST_BACKTRACE=1 ${pkgs.swayr}/bin/swayr ${cmd}";
  swayrd = "${systemd-cat "swayrd"} env RUST_BACKTRACE=1 ${pkgs.swayr}/bin/swayrd";
in
{
  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) {
    wayland.windowManager.sway = {
      extraConfig = exec swayrd;
      config.keybindings = {
        "${mod.super}+Space" = exec (swayr "switch-window");
        "${mod.super}+Delete" = exec (swayr "quit-window");
        "${mod.super}+Tab" = exec (swayr "switch-to-urgent-or-lru-window");
        "${mod.lalt }+Tab" = exec (swayr "prev-window all-workspaces");
        "${mod.lalt }+${mod.shift}+Tab" = exec (swayr "next-window all-workspaces");
        "${mod.super}+${mod.shift}+Space" = exec (swayr "switch-workspace-or-window");
        "${mod.super}+c" = exec (swayr "execute-swaymsg-command");
        "${mod.super}+${mod.shift}+c" = exec (swayr "execute-swayr-command");
      };
    };
  };
}

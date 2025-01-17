{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.kdn.desktop.sway;

  systemd-cat = name: "${pkgs.systemd}/bin/systemd-cat --identifier=${config.home.username}-${name}";
  exec = cmd: "exec '${cmd}'";

  swayr = cmd: "${systemd-cat "swayr"} env RUST_BACKTRACE=1 ${pkgs.swayr}/bin/swayr ${cmd}";
  swayrd = "${systemd-cat "swayrd"} env RUST_BACKTRACE=1 ${pkgs.swayr}/bin/swayrd";
in {
  config = lib.mkIf cfg.enable {
    wayland.windowManager.sway = {
      extraConfig = exec swayrd;
      config.keybindings = with config.kdn.desktop.sway.keys; {
        "${super}+Space" = exec (swayr "switch-window");
        "${super}+Delete" = exec (swayr "quit-window");
        "${super}+Tab" = exec (swayr "switch-to-urgent-or-lru-window");
        "${lalt}+Tab" = exec (swayr "prev-window all-workspaces");
        "${lalt}+${shift}+Tab" = exec (swayr "next-window all-workspaces");
        "${super}+${shift}+Space" = exec (swayr "switch-workspace-or-window");
        "${super}+C" = exec (swayr "execute-swaymsg-command");
        "${super}+${shift}+C" = exec (swayr "execute-swayr-command");
      };
    };
  };
}

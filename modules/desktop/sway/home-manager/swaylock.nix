{ nixosConfig, config, pkgs, lib, ... }:
let
  cfg = config.kdn.desktop.sway;
  sysCfg = nixosConfig.kdn.desktop.sway;

  swaylock = "${pkgs.swaylock}/bin/swaylock";
  lockCmd = "${swaylock} -f";
  swayPkg = config.wayland.windowManager.sway.package;
  swaymsg = "${swayPkg}/bin/swaymsg";

  mod = import ./_modifiers.nix;
in
{
  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) {
    wayland.windowManager.sway.config.keybindings."${mod.super}+L" = "exec ${lockCmd}";
    services.swayidle = {
      enable = true;
      systemdTarget = "kdn-sway-session.target";
      events = [
        { event = "before-sleep"; command = lockCmd; }
      ];
      timeouts = [
        {
          timeout = 300;
          command = lockCmd;
        }
        {
          timeout = 240;
          command = ''${swaymsg} "output * dpms off"'';
          resumeCommand = ''${swaymsg} "output * dpms on"'';
        }
      ];
    };
    systemd.user.services.swayidle.Unit = {
      Before = [ "kdn-sway-session.target" ];
      PartOf = [ "kdn-sway-session.target" ];
      After = [ "kdn-sway-envs.target" ];
      Requires = [ "kdn-sway-envs.target" ];
    };

    programs.swaylock.settings = {
      color = "000000";
      show-failed-attempts = true;
    };
  };
}

{ osConfig, config, pkgs, lib, ... }:
let
  cfg = config.kdn.desktop.sway;
  sysCfg = osConfig.kdn.desktop.sway;

  swaylock = "${pkgs.swaylock}/bin/swaylock";
  lockCmd = "${swaylock} -f";
  swayPkg = config.wayland.windowManager.sway.package;
  swaymsg = "${swayPkg}/bin/swaymsg";
in
{
  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) {
    wayland.windowManager.sway.config.keybindings."${cfg.keys.super}+L" = "exec ${lockCmd}";
    services.swayidle = {
      enable = true;
      systemdTarget = config.kdn.desktop.sway.systemd.session.target;
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
      Before = [ config.kdn.desktop.sway.systemd.session.target ];
      PartOf = [ config.kdn.desktop.sway.systemd.session.target ];
      After = [ config.kdn.desktop.sway.systemd.envs.target ];
      Requires = [ config.kdn.desktop.sway.systemd.envs.target ];
    };

    programs.swaylock.enable = true;
    programs.swaylock.settings = {
      show-failed-attempts = true;
    };
  };
}

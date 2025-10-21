{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.programs.keepassxc;

  envs.KEEPASS_PATH = builtins.concatStringsSep ":" cfg.service.searchDirs;

  finalPackage = config.kdn.programs.apps.keepassxc.package.final;
in
{
  options.kdn.programs.keepassxc = {
    enable = lib.mkEnableOption "keepassxc";

    service.enable = lib.mkEnableOption "keepassxc user service";
    service.searchDirs = lib.mkOption {
      type = with lib.types; listOf path;
    };
    service.fileName = lib.mkOption {
      type = with lib.types; str;
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = with pkgs; [
          finalPackage
          pkgs.kdn.kdn-keepass
        ];
        /*
          TODO: browser are enabled based on file presence
           in ~/.mozilla/native-messaging-hosts
           see https://github.com/keepassxreboot/keepassxc/blob/02881889d5b3dc533b8afafa47c0b0ac8054f2c1/src/browser/NativeMessageInstaller.cpp#L68-L93
        */
        kdn.programs.firefox.nativeMessagingHosts = [ finalPackage ];
        kdn.programs.thunderbird.nativeMessagingHosts = [ finalPackage ];
        kdn.programs.apps.keepassxc = {
          enable = true;
          dirs.cache = [
            "keepassxc" # holds the browser integration config?
          ];
          dirs.config = [
            "keepassxc"
          ];
          dirs.data = [ ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [
            "keepassxc"
          ];
        };
      }
      (lib.mkIf cfg.service.enable {
        /*
          TODO: configure programatically (View > Settings):
             - SSH Agent
               - Enable ... integration
             - Secret Service Integration
               - Enable ... integration
               - untick all except `Prompt to unlock database before searching`
             - General
               - Startup
                 - disable remembering previous databases
                 - disable showing expired entries
               - Entry Management
                 - `hide window when copying to clipboard` set to `Drop to background`
               - User Interface
                 - Show a system tray icon
                   - colorful
                   - hide to tray when minimized
             - Security
               - Convenience
                 - `Lock databases when session is locked or lid is closed`: false
               - Privacy
                 - use DDG for favicons
             - Browser Integration
               - Enable ... integration
               - enable for Firefox only
               - search in all opened databases
        */
        # TODO: entries list an entry preview were invisible, had to drag-resize from the edge
        home.sessionVariables = envs;
        systemd.user.services.keepassxc = {
          Unit.Description = "KeePassXC password manager";
          Service = {
            Slice = "background.slice";
            Type = "notify";
            NotifyAccess = "all";
            Environment = lib.attrsets.mapAttrsToList (key: value: "${key}=${value}") envs;
            ExecStart = lib.strings.escapeShellArgs [
              (lib.getExe pkgs.kdn.kdn-keepass)
              cfg.service.fileName
            ];
          };
          Unit.ConditionPathExists = cfg.service.searchDirs;
          Unit.Wants = [ "ssh-agent.service" ];
          Install.WantedBy = [ "graphical-session.target" ];
        };
      })
    ]
  );
}

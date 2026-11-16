{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.keepassxc;

  envs.KEEPASS_PATH = builtins.concatStringsSep ":" cfg.service.searchDirs;

  finalPackage = config.kdn.apps.keepassxc.package.final;
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

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      kdn.env.packages = [
        finalPackage
      ]
      /*
        The guard reads the platform, not the parent chain.

        `hasParentOfAnyType` walks the parent chain. A NixOS host has no NixOS parent, so the
        old guard hides the package on every host. It reaches the user profile alone.

        `pkgs.kdn.kdn-keepass` runs `sway` and `systemd`. `packages/default.nix` keeps it out
        of the Darwin package set, so the platform test is the correct one.
      */
      ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.kdn.kdn-keepass;
      # `KEEPASS_PATH` outlives the service: the `kdn-keepass` wrapper reads it to find the KDBX,
      # and a host may disable the service (rosec owns the bus) while still starting the GUI.
      kdn.env.variables = envs;
    })
    /*
      The forward needs its own guard. `service.enable` above stays outside `cfg.enable`,
      so this module cannot hoist one `lib.mkIf cfg.enable` over every branch.
    */
    (lib.mkIf cfg.enable (
      kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.programs.keepassxc = lib.mkDefault cfg; } ];
      }
    ))
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            /*
              TODO: browser are enabled based on file presence
               in ~/.mozilla/native-messaging-hosts
               see https://github.com/keepassxreboot/keepassxc/blob/02881889d5b3dc533b8afafa47c0b0ac8054f2c1/src/browser/NativeMessageInstaller.cpp#L68-L93
            */
            kdn.programs.firefox.nativeMessagingHosts = [ finalPackage ];
            kdn.programs.thunderbird.nativeMessagingHosts = [ finalPackage ];
            kdn.apps.keepassxc = {
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
                   - leave every "ask" checkbox OFF: `kdn-keepass` enforces
                     `UnlockBeforeSearch/ConfirmAccessItem/ConfirmDeleteItem=false` in the ini at
                     each start — a dialog nobody can click would wedge the login unlock or a
                     headless client (cold boot oams, 2026-11-14)
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
            systemd.user.services.keepassxc = {
              Unit.Description = "KeePassXC password manager";
              Service = {
                Slice = "background.slice";
                # `simple`, not `notify`: the wrapper unlocks with `pass`, which can wait for the
                # YubiKey/GPG agent. A `notify` unit waits for the readiness signal and is killed at
                # the 90 s start timeout, and every `org.freedesktop.secrets` client waits too.
                Type = "simple";
                # ...but `simple` sets NO `NOTIFY_SOCKET` unless access is granted, and the wrapper
                # needs it: it hands `MAINPID` to the KeePassXC child (`systemd-notify --pid`) and
                # signals readiness (`--ready`) once the database is UNLOCKED (a window exists and
                # the "Unlock Database" dialog is gone; matching any app_id window accepted that
                # dialog and lied to systemd — cold boot on oams, 2026-11-14). Without the handoff
                # the
                # unit tracks the expect wrapper, which exits as soon as `interact` sees no TTY;
                # systemd then stops the unit and `KillMode=control-group` kills KeePassXC, and the
                # next secret client re-activates the unit — an endless start/kill loop
                # (measured on oams, 2026-11-10). `NotifyAccess` was set to `all` before commit
                # 3f64b6114 dropped it together with `Type = "notify"`.
                NotifyAccess = "all";
                Restart = "on-failure";
                RestartSec = 5;
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
      )
    ))
  ];
}

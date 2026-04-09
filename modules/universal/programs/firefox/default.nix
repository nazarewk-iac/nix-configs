{
  lib,
  pkgs,
  config,
  kdnConfig,
  osConfig ? { },
  ...
}:
let
  cfg = config.kdn.programs.firefox;
  ffCfg = config.programs.firefox or { };
  appCfg = config.kdn.apps.firefox or { };

  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  profilesPath = if isDarwin then "${ffCfg.configPath or ""}/Profiles" else ffCfg.configPath or "";

  containerProfilesList = lib.pipe (ffCfg.profiles or { }) [
    builtins.attrValues
    (builtins.filter (p: (p.containers or { }) != { }))
  ];

  firefoxProfilePathsRel = lib.pipe containerProfilesList [
    (map (profile: "${profilesPath}/${profile.path}"))
  ];

  mkPref = Status: Value: { inherit Status Value; };
  mkPrefLocked = mkPref "locked";
  mkPrefDefault = mkPref "default";

  nativeMessagingHostsAreSupported = !pkgs.stdenv.isDarwin;
in
{
  options.kdn.programs.firefox = {
    enable = lib.mkEnableOption "firefox setup";
    profileNames = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
    nativeMessagingHosts = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
      description = lib.mdDoc ''
        Additional packages containing native messaging hosts that should be made available to Firefox extensions.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.programs.firefox.enable = true; } ];
      })
      (kdnConfig.util.ifHM (
        lib.mkMerge [
          {
            # work around warning at https://github.com/danth/stylix/blob/6a2e5258876c46b62edacb3e51a759ed1c06332b/modules/firefox/hm.nix#L171
            stylix.targets.firefox.profileNames = cfg.profileNames;
            home.packages = [
              pkgs.kdn.ff-ctl
            ];
            programs.firefox.enable = true;
            programs.firefox.package = appCfg.package.final;
            kdn.apps.firefox = {
              package.install = false;
              package.original =
                if !nativeMessagingHostsAreSupported then pkgs.firefox-unwrapped else pkgs.firefox;
              dirs.cache = [ ];
              dirs.config = [ ];
              dirs.data = [ "/.mozilla/firefox" ];
              dirs.disposable = [ ];
              dirs.reproducible = [ ];
              dirs.state = [ ];
              package.overlays =
                [ ]
                ++ lib.lists.optional nativeMessagingHostsAreSupported (old: {
                  nativeMessagingHosts = old.nativeMessagingHosts or [ ] ++ cfg.nativeMessagingHosts;
                });
            };

            home.file = lib.mkIf nativeMessagingHostsAreSupported {
              ".mozilla/native-messaging-hosts".force = true;
            };
          }
          {
            kdn.programs.firefox.nativeMessagingHosts = lib.kdn.pkg.onlySupported pkgs pkgs.kdePackages.plasma-browser-integration;
          }
          (lib.mkIf (firefoxProfilePathsRel != { }) {
            home.file = lib.pipe firefoxProfilePathsRel [
              (map (path: {
                name = "${path}/containers.json";
                value.target = "${path}/containers.json.d/50-hm-containers.json";
              }))
              builtins.listToAttrs
            ];

            systemd.user.paths.firefox-containers-d-sync = {
              Install.WantedBy = [ "default.target" ];
              Unit.Description = "merges pieces into Firefox's containers.json file";
              Path = {
                PathChanged = lib.pipe firefoxProfilePathsRel [
                  (map (path: "${config.home.homeDirectory}/${path}/containers.json.d"))
                ];
                TriggerLimitBurst = "1";
                TriggerLimitIntervalSec = "1s";
              };
            };
            systemd.user.services.firefox-containers-d-sync = {
              Install.WantedBy = [ "default.target" ];
              Unit.Description = "merges pieces into Firefox's containers.json file";
              Service = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = lib.strings.escapeShellArgs [
                  (lib.getExe pkgs.kdn.ff-ctl)
                  "containers-config-render"
                ];
              };
            };
          })
          {
            programs.firefox.policies = osConfig.programs.firefox.policies or { };
            programs.firefox.languagePacks = lib.mkDefault osConfig.programs.firefox.languagePacks or [ ];
          }
          {
            programs.firefox.languagePacks = lib.mkDefault [
              "en-GB"
              "pl"
            ];

            programs.firefox.policies = {
              DisableFirefoxStudies = true;
              DisablePocket = true;
              DisableProfileImport = true;
              DisableTelemetry = true;
              DontCheckDefaultBrowser = true;
              NoDefaultBookmarks = true;
              Preferences."browser.startup.page" = mkPrefDefault "3";
              Preferences."browser.tabs.warnOnClose" = mkPrefLocked "1";
              Preferences."widget.use-xdg-desktop-portal.file-picker" = mkPrefLocked "1";
              PromptForDownloadLocation = true;
              SearchBar = "unified";
              TranslateEnabled = true;
            };
          }
          {
            programs.firefox.policies = {
              OverrideFirstRunPage = "";
              OverridePostUpdatePage = "";
              Preferences."browser.startup.homepage_override.mstone" = mkPrefLocked "ignore";
            };
          }
          {
            programs.firefox.policies = {
              GenerativeAI.Enabled = false;
            };
          }
        ]
      ))
    ]
  );
}

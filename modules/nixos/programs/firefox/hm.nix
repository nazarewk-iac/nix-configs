{
  lib,
  pkgs,
  config,
  osConfig,
  ...
}: let
  cfg = config.kdn.programs.firefox;
  ffCfg = config.programs.firefox;
  appCfg = config.kdn.programs.apps.firefox;

  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  profilesPath =
    if isDarwin
    then "${ffCfg.configPath}/Profiles"
    else ffCfg.configPath;

  containerProfilesList = lib.pipe ffCfg.profiles [
    builtins.attrValues
    (builtins.filter (p: p.containers != {}))
  ];

  firefoxProfilePathsRel = lib.pipe containerProfilesList [
    (builtins.map (profile: "${profilesPath}/${profile.path}"))
  ];

  /*
  Status can be “default”, “locked”, “user” or “clear”
      "default": Read/Write: Settings appear as default even if factory default differs.
      "locked": Read-Only: Settings appear as default even if factory default differs.
      "user": Read/Write: Settings appear as changed if it differs from factory default.
      "clear": Read/Write: Value has no effect. Resets to factory defaults on each startup.
  */
  mkPref = Status: Value: {inherit Status Value;};
  mkPrefLocked = mkPref "locked";
  mkPrefDefault = mkPref "default";
in {
  options.kdn.programs.firefox = {
    enable = lib.mkEnableOption "firefox setup";
    nativeMessagingHosts = lib.mkOption {
      type = with lib.types; listOf package;
      default = [];
      description = lib.mdDoc ''
        Additional packages containing native messaging hosts that should be made available to Firefox extensions.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages = with pkgs; [
        kdn.ff-ctl
      ];
      programs.firefox.enable = true;
      programs.firefox.package = appCfg.package.final;
      kdn.programs.apps.firefox = {
        package.install = false;
        dirs.cache = [];
        dirs.config = [];
        dirs.data = ["/.mozilla/firefox"];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
        package.overlays = [
          (old: {nativeMessagingHosts = old.nativeMessagingHosts or [] ++ cfg.nativeMessagingHosts;})
        ];
      };
      home.file.".mozilla/native-messaging-hosts".force = true;
    }
    {
      kdn.programs.firefox.nativeMessagingHosts = with pkgs; [kdePackages.plasma-browser-integration];
    }
    (lib.mkIf (firefoxProfilePathsRel != {}) {
      home.file = lib.pipe firefoxProfilePathsRel [
        (builtins.map (path: {
          name = "${path}/containers.json";
          value.target = "${path}/containers.json.d/50-hm-containers.json";
        }))
        builtins.listToAttrs
      ];

      systemd.user.paths.firefox-containers-d-sync = {
        Install.WantedBy = ["default.target"];
        Unit = {
          Description = "merges pieces into Firefox's containers.json file";
        };
        Path = {
          PathChanged = lib.pipe firefoxProfilePathsRel [
            (builtins.map (path: "${config.home.homeDirectory}/${path}/containers.json.d"))
          ];
          TriggerLimitBurst = "1";
          TriggerLimitIntervalSec = "1s";
        };
      };
      systemd.user.services.firefox-containers-d-sync = {
        Install.WantedBy = ["default.target"];
        Unit = {
          Description = "merges pieces into Firefox's containers.json file";
        };
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
      programs.firefox.policies = osConfig.programs.firefox.policies;
      programs.firefox.languagePacks = lib.mkDefault osConfig.programs.firefox.languagePacks;
    }
    {
      programs.firefox.languagePacks = lib.mkDefault ["en-GB" "pl"];

      # see https://discourse.nixos.org/t/combining-best-of-system-firefox-and-home-manager-firefox-settings/37721
      programs.firefox.policies = {
        # see https://mozilla.github.io/policy-templates/
        DisableFirefoxStudies = true;
        DisablePocket = true;
        DisableProfileImport = true;
        DisableTelemetry = true;
        DontCheckDefaultBrowser = true;
        NoDefaultBookmarks = true;
        Preferences."browser.startup.page" = mkPrefDefault "3"; # Open previous windows and tabs
        Preferences."browser.tabs.warnOnClose" = mkPrefLocked "1";
        Preferences."widget.use-xdg-desktop-portal.file-picker" = mkPrefLocked "1";
        PromptForDownloadLocation = true;
        SearchBar = "unified";
        TranslateEnabled = true;
      };
    }
    {
      # disable first run and update wizards
      programs.firefox.policies = {
        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";

        Preferences."browser.startup.homepage_override.mstone" = mkPrefLocked "ignore";
      };
    }
  ]);
}

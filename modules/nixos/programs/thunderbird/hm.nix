{
  lib,
  pkgs,
  config,
  osConfig ? {},
  ...
}: let
  cfg = config.kdn.programs.thunderbird;
  appCfg = config.kdn.programs.apps.thunderbird;

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

  # see https://github.com/NixOS/nixpkgs/issues/366581#issuecomment-2564737818
  nativeMessagingHostsAreSupported = !pkgs.stdenv.isDarwin;
in {
  options.kdn.programs.thunderbird = {
    enable = lib.mkEnableOption "thunderbird setup";
    profileNames = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
    };
    nativeMessagingHosts = lib.mkOption {
      type = with lib.types; listOf package;
      default = [];
      description = lib.mdDoc ''
        Additional packages containing native messaging hosts that should be made available to Firefox extensions.
      '';
    };
    policies = lib.mkOption {
      type = (pkgs.formats.json {}).type;
      default = {};
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # work around warning at https://github.com/danth/stylix/blob/6a2e5258876c46b62edacb3e51a759ed1c06332b/modules/thunderbird/hm.nix#L171
      programs.thunderbird.enable = true;
      programs.thunderbird.package = appCfg.package.final;
      programs.thunderbird.profiles.main.isDefault = true;
      kdn.programs.apps.thunderbird = {
        package.install = false;
        package.original = pkgs.thunderbird;
        dirs.cache = [];
        dirs.config = [];
        dirs.data = ["/.thunderbird"];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
        package.overlays =
          [
            (old: {extraPoliciesFiles = [(pkgs.writeJSON "hm-policies.json" cfg.policies)];})
          ]
          ++ lib.lists.optional nativeMessagingHostsAreSupported (old: {
            nativeMessagingHosts = old.nativeMessagingHosts or [] ++ cfg.nativeMessagingHosts;
          });
      };
    }
    {
      kdn.programs.thunderbird.nativeMessagingHosts = lib.kdn.pkg.onlySupported pkgs pkgs.kdePackages.plasma-browser-integration;
    }
    {
      kdn.programs.thunderbird.policies = osConfig.programs.thunderbird.policies or {};
    }
    {
      kdn.programs.thunderbird.policies = {
        # TODO: verify whether policies apply to thunderbird
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
      kdn.programs.thunderbird.policies = {
        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";
      };
    }
  ]);
}

{
  lib,
  pkgs,
  config,
  kdnConfig,
  osConfig ? {},
  ...
}: {
  options.kdn.programs.thunderbird = {
    enable = lib.mkEnableOption "thunderbird setup";
    nativeMessagingHosts = lib.mkOption {
      type = with lib.types; listOf package;
      default = [];
    };
  };

  imports = [
    ({...}:
    let
      cfg = config.kdn.programs.thunderbird;
      appCfg = config.kdn.apps.thunderbird;

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

config = kdnConfig.util.ifHM (lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            # work around warning at https://github.com/danth/stylix/blob/6a2e5258876c46b62edacb3e51a759ed1c06332b/modules/thunderbird/hm.nix#L171
            programs.thunderbird.enable = true;
            programs.thunderbird.package = appCfg.package.final;
            programs.thunderbird.profiles.main.isDefault = true;
            kdn.apps.thunderbird = {
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
        ]
      ));
    }
    )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.programs.thunderbird;
        in {

          config = lib.mkIf cfg.enable (
              lib.mkMerge [
              (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.programs.thunderbird = lib.mkDefault cfg;}];})
{home-manager.sharedModules = [{kdn.programs.thunderbird.enable = true;}];}
            ]
          );
        }
      )
    )
  ];
}

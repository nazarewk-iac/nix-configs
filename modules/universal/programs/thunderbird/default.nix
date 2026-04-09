{
  lib,
  pkgs,
  config,
  kdnConfig,
  osConfig ? { },
  ...
}:
let
  cfg = config.kdn.programs.thunderbird;
in
{
  options.kdn.programs.thunderbird = {
    enable = lib.mkEnableOption "thunderbird setup";
    nativeMessagingHosts = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
    };
    policies = lib.mkOption {
      type = with lib.types; attrsOf anything;
      default = { };
    };
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { kdn.programs.thunderbird.enable = true; } ];
      }
    ))
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            # work around warning at https://github.com/danth/stylix/blob/6a2e5258876c46b62edacb3e51a759ed1c06332b/modules/thunderbird/hm.nix#L171
            programs.thunderbird.enable = true;
            programs.thunderbird.package = config.kdn.apps.thunderbird.package.final;
            programs.thunderbird.profiles.main.isDefault = true;
            kdn.apps.thunderbird = {
              package.install = false;
              package.original = pkgs.thunderbird;
              dirs.cache = [ ];
              dirs.config = [ ];
              dirs.data = [ "/.thunderbird" ];
              dirs.disposable = [ ];
              dirs.reproducible = [ ];
              dirs.state = [ ];
              package.overlays = [
                (old: {
                  extraPoliciesFiles = [ (pkgs.writeText "hm-policies.json" (builtins.toJSON cfg.policies)) ];
                })
              ]
              # see https://github.com/NixOS/nixpkgs/issues/366581#issuecomment-2564737818
              ++ lib.lists.optional (!pkgs.stdenv.isDarwin) (old: {
                nativeMessagingHosts = old.nativeMessagingHosts or [ ] ++ cfg.nativeMessagingHosts;
              });
            };
          }
          {
            kdn.programs.thunderbird.nativeMessagingHosts = lib.kdn.pkg.onlySupported pkgs pkgs.kdePackages.plasma-browser-integration;
          }
          {
            kdn.programs.thunderbird.policies = osConfig.programs.thunderbird.policies or { };
          }
          {
            # TODO: verify whether policies apply to thunderbird
            # see https://mozilla.github.io/policy-templates/
            /*
              Status can be "default", "locked", "user" or "clear"
                  "default": Read/Write: Settings appear as default even if factory default differs.
                  "locked": Read-Only: Settings appear as default even if factory default differs.
                  "user": Read/Write: Settings appear as changed if it differs from factory default.
                  "clear": Read/Write: Value has no effect. Resets to factory defaults on each startup.
            */
            kdn.programs.thunderbird.policies = {
              DisableFirefoxStudies = true;
              DisablePocket = true;
              DisableProfileImport = true;
              DisableTelemetry = true;
              DontCheckDefaultBrowser = true;
              NoDefaultBookmarks = true;
              Preferences."browser.startup.page" = {
                # Open previous windows and tabs
                Status = "default";
                Value = "3";
              };
              Preferences."browser.tabs.warnOnClose" = {
                Status = "locked";
                Value = "1";
              };
              Preferences."widget.use-xdg-desktop-portal.file-picker" = {
                Status = "locked";
                Value = "1";
              };
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
      )
    ))
  ];
}

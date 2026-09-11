# `kdn.programs.thunderbird`, as a den aspect.
# It ports `modules/universal/programs/thunderbird/default.nix`.
#
# Home Manager only. The old module reads `osConfig.programs.thunderbird.policies`; an aspect reads no
# parent host config, so a consumer writes a host-wide policy set into `policies` here instead.
{ kdn, ... }:
{
  kdn.program-thunderbird.includes = [ kdn.apps ];

  kdn.program-thunderbird.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.thunderbird;

      # `lib.kdn.pkg.onlySupported`, inlined.
      onlySupported = builtins.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform);
    in
    {
      options.kdn.programs.thunderbird.nativeMessagingHosts = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = ''
          Packages that hold a native messaging host for a Thunderbird extension.

          Two plain definitions of this list concatenate. Never put `lib.mkDefault` on it.
        '';
      };

      options.kdn.programs.thunderbird.policies = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          Enterprise policies the aspect writes into a policy file.

          See https://mozilla.github.io/policy-templates/. `Status` takes "default", "locked", "user"
          or "clear".
        '';
      };

      config = lib.mkMerge [
        {
          programs.thunderbird.enable = true;
          programs.thunderbird.package = config.kdn.apps.thunderbird.package.final;
          programs.thunderbird.profiles.main.isDefault = true;

          kdn.apps.thunderbird = {
            enable = true;
            # `programs.thunderbird` installs the package.
            package.install = false;
            package.original = pkgs.thunderbird;
            # The leading `/` makes the path relative to the home directory.
            dirs.data = [ "/.thunderbird" ];
            package.overlays = [
              (old: {
                extraPoliciesFiles = [ (pkgs.writeText "hm-policies.json" (builtins.toJSON cfg.policies)) ];
              })
            ]
            # See https://github.com/NixOS/nixpkgs/issues/366581#issuecomment-2564737818
            ++ lib.optional (!pkgs.stdenv.hostPlatform.isDarwin) (old: {
              nativeMessagingHosts = old.nativeMessagingHosts or [ ] ++ cfg.nativeMessagingHosts;
            });
          };

          kdn.programs.thunderbird.nativeMessagingHosts = onlySupported [
            pkgs.kdePackages.plasma-browser-integration
          ];
        }
        {
          kdn.programs.thunderbird.policies = {
            DisableFirefoxStudies = true;
            DisablePocket = true;
            DisableProfileImport = true;
            DisableTelemetry = true;
            DontCheckDefaultBrowser = true;
            NoDefaultBookmarks = true;
            # Open the previous windows and tabs.
            Preferences."browser.startup.page" = {
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
          # Turn the first-run and the update wizard off.
          kdn.programs.thunderbird.policies = {
            OverrideFirstRunPage = "";
            OverridePostUpdatePage = "";
          };
        }
      ];
    };
}

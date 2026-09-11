# `kdn.programs.firefox`, as a den aspect.
# It ports `modules/universal/programs/firefox/default.nix`.
#
# Home Manager only. The old module also writes `kdn.env.packages` with `ff-ctl` from a shared branch;
# that write lands in the `homeManager` target here, because every consumer is a user evaluation.
#
# ## Two host reads the port drops
#
# The old module reads `osConfig.programs.firefox.policies` and
# `osConfig.programs.firefox.languagePacks`. An aspect reads no parent host config. A consumer that
# wants a host-wide policy set writes it into the user's own `programs.firefox.policies`.
{ kdn, ... }:
{
  kdn.program-firefox.includes = [ kdn.apps ];

  kdn.program-firefox.homeManager =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.firefox;
      ffCfg = config.programs.firefox;
      appCfg = config.kdn.apps.firefox;

      inherit (pkgs.stdenv.hostPlatform) isDarwin;
      profilesPath = if isDarwin then "${ffCfg.configPath}/Profiles" else ffCfg.configPath;

      containerProfilesList = lib.pipe ffCfg.profiles [
        builtins.attrValues
        (builtins.filter (p: (p.containers or { }) != { }))
      ];

      firefoxProfilePathsRel = map (profile: "${profilesPath}/${profile.path}") containerProfilesList;

      mkPref = Status: Value: { inherit Status Value; };
      mkPrefLocked = mkPref "locked";
      mkPrefDefault = mkPref "default";

      nativeMessagingHostsAreSupported = !isDarwin;

      # A plain `callPackage` route, with no overlay. `pkgs.kdn.ff-ctl` needs this repository's own
      # overlay, and a relative path literal needs none.
      ff-ctl = pkgs.callPackage ../../../packages/ff-ctl { };

      # `lib.kdn.pkg.onlySupported`, inlined. It keeps a package only when the platform supports it.
      onlySupported = builtins.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform);
    in
    {
      options.kdn.programs.firefox.profileNames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Profile names the stylix firefox target styles.

          Two plain definitions of this list concatenate. Never put `lib.mkDefault` on it.
        '';
      };

      options.kdn.programs.firefox.nativeMessagingHosts = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = ''
          Packages that hold a native messaging host for a Firefox extension.

          Two plain definitions of this list concatenate. Never put `lib.mkDefault` on it.
        '';
      };

      config = lib.mkMerge [
        {
          home.packages = [ ff-ctl ];

          # The current home-manager default moved to `${config.xdg.configHome}/mozilla/firefox`. This
          # line keeps the legacy path while `home.stateVersion` is older than 26.05, and it silences
          # the warning.
          programs.firefox.configPath = lib.mkIf (lib.versionOlder config.home.stateVersion "26.05") (
            lib.mkDefault ".mozilla/firefox"
          );
          programs.firefox.enable = true;
          programs.firefox.package = appCfg.package.final;

          kdn.apps.firefox = {
            enable = true;
            # `programs.firefox` installs the package.
            package.install = false;
            dirs.config = [ "mozilla/firefox" ];
            # The leading `/` makes the path relative to the home directory.
            dirs.data = [ "/.mozilla/firefox" ];
            package.overlays = lib.optional nativeMessagingHostsAreSupported (old: {
              nativeMessagingHosts = old.nativeMessagingHosts or [ ] ++ cfg.nativeMessagingHosts;
            });
          };

          home.file = lib.mkIf nativeMessagingHostsAreSupported {
            ".mozilla/native-messaging-hosts".force = true;
          };
        }

        {
          kdn.programs.firefox.nativeMessagingHosts = onlySupported [
            pkgs.kdePackages.plasma-browser-integration
          ];
        }

        # stylix is optional in a den evaluation, so the write tests the option tree first. It works
        # around the warning at
        # https://github.com/danth/stylix/blob/6a2e5258876c46b62edacb3e51a759ed1c06332b/modules/firefox/hm.nix#L171
        (lib.optionalAttrs (options ? stylix) { stylix.targets.firefox.profileNames = cfg.profileNames; })

        (lib.mkIf (firefoxProfilePathsRel != [ ]) {
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
              PathChanged = map (
                path: "${config.home.homeDirectory}/${path}/containers.json.d"
              ) firefoxProfilePathsRel;
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
                (lib.getExe ff-ctl)
                "containers-config-render"
              ];
            };
          };
        })

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
            # Open the previous windows and tabs.
            Preferences."browser.startup.page" = mkPrefDefault "3";
            Preferences."browser.tabs.warnOnClose" = mkPrefLocked "1";
            Preferences."widget.use-xdg-desktop-portal.file-picker" = mkPrefLocked "1";
            PromptForDownloadLocation = true;
            SearchBar = "unified";
            TranslateEnabled = true;
          };
        }
        {
          # Turn the first-run and the post-update wizard off.
          programs.firefox.policies = {
            OverrideFirstRunPage = "";
            OverridePostUpdatePage = "";
            Preferences."browser.startup.homepage_override.mstone" = mkPrefLocked "ignore";
          };
        }
        {
          programs.firefox.policies.GenerativeAI.Enabled = false;
        }
      ];
    };
}

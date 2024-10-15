{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.firefox;
  ffCfg = config.programs.firefox;
  appCfg = config.kdn.programs.apps.firefox;

  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  profilesPath =
    if isDarwin then "${ffCfg.configPath}/Profiles" else ffCfg.configPath;

  containerProfilesList = lib.pipe ffCfg.profiles [
    builtins.attrValues
    (builtins.filter (p: p.containers != { }))
  ];

  firefoxProfilePathsRel = lib.pipe containerProfilesList [
    (builtins.map (profile: "${profilesPath}/${profile.path}"))
  ];
in
{
  options.kdn.programs.firefox = {
    enable = lib.mkEnableOption "firefox setup";
    nativeMessagingHosts = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
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
        dirs.cache = [ ];
        dirs.config = [ ];
        dirs.data = [ "/.mozilla/firefox" ];
        dirs.disposable = [ ];
        dirs.reproducible = [ ];
        dirs.state = [ ];
        package.overlays = [
          (old: { nativeMessagingHosts = old.nativeMessagingHosts or [ ] ++ cfg.nativeMessagingHosts; })
        ];
      };
      home.file.".mozilla/native-messaging-hosts".force = true;
    }
    {
      kdn.programs.firefox.nativeMessagingHosts = with pkgs; [ libsForQt5.plasma-browser-integration ];
    }
    (lib.mkIf (firefoxProfilePathsRel != { }) {
      home.file = lib.pipe firefoxProfilePathsRel [
        (builtins.map (path: {
          name = "${path}/containers.json";
          value.target = "${path}/containers.json.d/50-hm-containers.json";
        }))
        builtins.listToAttrs
      ];

      systemd.user.paths.firefox-containers-d-sync = {
        Install.WantedBy = [ "default.target" ];
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
        Install.WantedBy = [ "default.target" ];
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
  ]);
}

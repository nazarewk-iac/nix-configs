{
  config,
  pkgs,
  lib,
  ...
}: let
  shellCfg = config.services.nwg-shell;
  cfg = shellCfg.panel;
  inherit (shellCfg._lib) mkComponent;

  panelConfigToNix = output:
    lib.pipe output [
      (lib.lists.imap0 (idx: panel:
        lib.nameValuePair panel.name (panel
          // {
            order = lib.mkDefault (idx * 100);
            enable = lib.mkDefault true;
          })))
      builtins.listToAttrs
    ];
  panelConfigToJSON = input:
    lib.pipe input [
      builtins.attrValues
      (builtins.filter (panel: panel.enable or true))
      (builtins.sort (a: b: builtins.lessThan a.order b.order))
      (builtins.map (panel: builtins.removeAttrs panel ["enable" "order"]))
    ];
in {
  options.services.nwg-shell.panel = mkComponent "panel" {
    config = lib.mkOption {
      type = (pkgs.formats.json {}).type;
      apply = panelConfigToJSON;
    };
    style = lib.mkOption {
      type = with lib.types; str;
    };
  };
  config = lib.mkIf (shellCfg.enable && cfg.enable) (lib.mkMerge [
    {
      services.nwg-shell.panel.config = lib.pipe ./default-config.json [
        builtins.readFile
        builtins.fromJSON
        panelConfigToNix
      ];
    }
    {
      # TODO: missing tray icons for electron based apps https://github.com/nwg-piotr/nwg-panel/issues/224
      home.packages = with pkgs; [
        gopsuinfo # for various executors
      ];
      services.nwg-shell.panel.style = builtins.readFile "${cfg.package}/${pkgs.python3.sitePackages}/nwg_panel/config/style.css";
      services.nwg-shell.panel.config.panel-top.output = lib.mkForce "All";
      services.nwg-shell.panel.config.panel-bottom.output = lib.mkForce "All";
      systemd.user.services.nwg-panel = {
        Install = {
          WantedBy = ["graphical-session.target"];
        };
        Unit = {
          Description = "nwg-panel: GTK3-based panel for sway window manager";
          Documentation = "https://github.com/nwg-piotr/nwg-panel";
          PartOf = ["graphical-session.target"];
          After = ["graphical-session-pre.target"];
          ConditionEnvironment = "WAYLAND_DISPLAY";
        };
        Service = {
          Type = "simple";
          ExecStartPre = lib.getExe (pkgs.writeShellApplication {
            name = "nwg-panel-set-configs";
            runtimeInputs = with pkgs; [diffutils jq];
            runtimeEnv.config_path = "${config.xdg.configHome}/nwg-panel/config";
            runtimeEnv.calendar_path = "${config.xdg.configHome}/nwg-panel/calendar.json";
            runtimeEnv.managed_config_path =
              pkgs.runCommand "nwg-panel.config.json"
              {
                # see https://github.com/NixOS/nixpkgs/blob/92678837b311e85ab8d9f94bf6755c6ecb0f569f/pkgs/pkgs-lib/formats.nix#L64-L70
                nativeBuildInputs = with pkgs; [jq];
                value = builtins.toJSON cfg.config;
                passAsFile = ["value"];
              } ''jq -S . "$valuePath"> $out'';
            text = ''
              tempdir="$(mktemp -d /tmp/nwg-panel-set-configs.XXXXXX)"
              trap 'rm -rf "$tempdir" || :' EXIT
              mkdir -p "$tempdir"
              test -e "$calendar_path" || jq -n '{}' >"$calendar_path"
              if test -e "$config_path" ; then
                jq -S '.' "$config_path" > "$tempdir/config.json"
              else
                jq -n '{}' >"$config_path"
              fi
              if ! diff "$managed_config_path" "$tempdir/config.json" ; then
                echo "current config has changed, replacing with managed"
                cp "$managed_config_path" "$config_path"
              fi
              rm -r "$tempdir"
            '';
          });
          ExecStart = lib.getExe cfg.package;
          Restart = "on-failure";
        };
      };
    }
  ]);
}

{ config, pkgs, lib, ... }:
let
  shellCfg = config.services.nwg-shell;
  cfg = shellCfg.panel;
  inherit (shellCfg._lib) mkComponent;

  panelConfigToNix = output: lib.pipe output [
    (lib.lists.imap0 (idx: panel: lib.nameValuePair panel.name (panel // {
      order = lib.mkDefault (idx * 100);
      enable = lib.mkDefault true;
    })))
    builtins.listToAttrs
  ];
  panelConfigToJSON = input: lib.pipe input [
    builtins.attrValues
    (builtins.filter (panel: panel.enable or true))
    (builtins.sort (a: b: builtins.lessThan a.order b.order))
    (builtins.map (panel: builtins.removeAttrs panel [ "enable" "order" ]))
  ];
in
{
  options.services.nwg-shell.panel = mkComponent "panel" {
    config = lib.mkOption {
      type = (pkgs.formats.json { }).type;
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
        #(lib.attrsets.mapAttrsRecursive (path: value: let t = builtins.typeOf value; in if t == "list" || t == "set" then value else lib.mkDefault value))
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
      xdg.configFile."nwg-panel/config.managed.json".text = builtins.toJSON cfg.config;
      systemd.user.services.nwg-panel = {
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
        Unit = {
          Description = "nwg-panel: GTK3-based panel for sway window manager";
          Documentation = "https://github.com/nwg-piotr/nwg-panel";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session-pre.target" ];
          ConditionEnvironment = "WAYLAND_DISPLAY";
        };
        Service = {
          Type = "simple";
          ExecStartPre = lib.getExe (pkgs.writeShellApplication {
            name = "nwg-panel-set-configs";
            runtimeInputs = with pkgs; [ diffutils jq ];
            text = ''
              config_dir="$XDG_CONFIG_HOME/nwg-panel"
              jq -S '.' "$config_dir/config.managed.json" >"$config_dir/config.managed.pretty.json"
              if test -e "$config_dir/config" ; then
                jq -S '.' "$config_dir/config" > "$config_dir/config.pretty.json"
              else
                jq -n '{}' >"$config_dir/config.pretty.json"
              fi
              if ! diff "$config_dir/config.managed.pretty.json" "$config_dir/config.pretty.json" ; then
                echo "current config has changed, replacing with managed"
                cp "$config_dir/config.managed.json" "$config_dir/config"
              fi
              rm "$config_dir/config"*".pretty.json"
            '';
          });
          ExecStart = lib.getExe cfg.package;
          Restart = "on-failure";
        };
      };
    }
  ]);
}

{ config, pkgs, lib, ... }:
let
  cfg = config.services.nwg-shell;

  mkComponent = name: extra: {
    enable = lib.mkOption { type = with lib.types; bool; default = true; };
    package = lib.mkOption { type = with lib.types; package; default = pkgs."nwg-${name}"; };
  } // extra;

  panelConfigTo = output: lib.pipe output [
    (lib.lists.imap0 (idx: panel: lib.nameValuePair panel.name (panel // {
      order = lib.mkDefault (idx * 100);
      enable = lib.mkDefault true;
    })))
    builtins.listToAttrs
  ];
  panelConfigFrom = input: lib.pipe input [
    builtins.attrValues
    (builtins.filter (panel: panel.enable or true))
    (builtins.sort (a: b: builtins.lessThan a.order b.order))
    (builtins.map (panel: builtins.removeAttrs panel [ "enable" "order" ]))
  ];
in
{
  options.services.nwg-shell = {
    enable = lib.mkEnableOption "nwg-shell package suite setup";

    bar = mkComponent "bar" { };
    displays = mkComponent "displays" { };
    dock = mkComponent "dock" { };
    drawer = mkComponent "drawer" {
      opts = lib.mkOption {
        type = with lib.types; attrsOf (oneOf [ str true ]);
        description = ''
          see https://github.com/nwg-piotr/nwg-drawer
        '';
        default = { };
        apply = opts: lib.pipe opts [
          (lib.attrsets.mapAttrsToList (name: value: [ "-${name}" ] ++ lib.optional (builtins.typeOf value == "string") value))
          lib.lists.flatten
        ];
      };
      exec = lib.mkOption {
        readOnly = true;
        default = builtins.toString (pkgs.writeScript "nwg-drawer-launch" ''
          ${lib.getExe cfg.drawer.package} ${builtins.concatStringsSep " " cfg.drawer.opts}
        '');
      };
    };
    hello = mkComponent "hello" { };
    look = mkComponent "look" { };
    menu = mkComponent "menu" { };
    panel = mkComponent "panel" {
      defaults = lib.mkOption {
        readOnly = true;
        default = pkgs.runCommand "nwg-panel-default-config" { } ''
          export PATH="${lib.makeBinPath (with pkgs; [xvfb-run coreutils tree])}:$PATH"
          mkdir -p "$PWD/home"
          (
            export HOME="$PWD/home"
            export LANG=en_US.UTF-8

            xvfb-run --auto-servernum -- \
              '${lib.getExe cfg.panel.package}'
          ) &
          pid=$!
          until test -e "$PWD/home/.config/nwg-panel/config" ; do
            sleep 1
          done
          kill $pid
          mkdir -p "$out"
          mv "$PWD/home/.config/nwg-panel" "$out/config"
          mv "$PWD/home/.local/share/nwg-panel" "$out/data"
          tree -a "$out"
        '';
      };
      config = lib.mkOption {
        type = (pkgs.formats.json { }).type;
        #apply = panelConfigFrom;
      };
      style = lib.mkOption {
        type = with lib.types; str;
      };
    };
    wrapper = mkComponent "wrapper" { };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.swaync.enable = true;
      home.packages = lib.pipe cfg [
        (lib.filterAttrs (n: v: (v.enable or false) && v ? package))
        builtins.attrValues
        (builtins.map (v: v.package))
      ];
      services.nwg-shell.drawer.opts.wm = ''"$XDG_CURRENT_DESKTOP"'';
    }
    (lib.mkIf cfg.panel.enable {
      # TODO: declarative config building on top of default configs: https://github.com/nwg-piotr/nwg-panel/issues/289
      # see https://github.com/nwg-piotr/nwg-panel/issues/289#issuecomment-2075997316
      services.nwg-shell.panel.config = lib.pipe ./nwg-panel/default-config.json [
        builtins.readFile
        builtins.fromJSON
        panelConfigTo
      ];
    })
    (lib.mkIf cfg.panel.enable {
      # TODO: missing tray icons for electron based apps https://github.com/nwg-piotr/nwg-panel/issues/224
      home.packages = with pkgs; [
        gopsuinfo # for various executors
      ];
      services.nwg-shell.panel.style = builtins.readFile "${cfg.panel.package}/${pkgs.python3.sitePackages}/nwg_panel/config/style.css";
      services.nwg-shell.panel.config.panel-top.output = "All";
      services.nwg-shell.panel.config.panel-bottom.output = "All";

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
          ExecStart = lib.getExe cfg.panel.package;
          Restart = "on-failure";
        };
      };
    })
  ]);
}

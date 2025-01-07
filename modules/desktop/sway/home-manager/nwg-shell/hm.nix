{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.nwg-shell;
  inherit (cfg._lib) mkComponent;
in {
  options.services.nwg-shell = {
    enable = lib.mkEnableOption "nwg-shell package suite setup";

    _lib = lib.mkOption {
      readOnly = true;
      internal = true;
      default = {
        mkComponent = name: extra:
          {
            enable = lib.mkOption {
              type = with lib.types; bool;
              default = true;
            };
            package = lib.mkOption {
              type = with lib.types; package;
              default = pkgs."nwg-${name}";
            };
          }
          // extra;
      };
    };

    bar = mkComponent "bar" {};
    displays = mkComponent "displays" {};
    dock = mkComponent "dock" {};
    drawer = mkComponent "drawer" {
      opts = lib.mkOption {
        type = with lib.types; attrsOf (oneOf [str true]);
        description = ''
          see https://github.com/nwg-piotr/nwg-drawer
        '';
        default = {};
        apply = opts:
          lib.pipe opts [
            (lib.attrsets.mapAttrsToList (name: value: ["-${name}"] ++ lib.optional (builtins.typeOf value == "string") value))
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
    hello = mkComponent "hello" {};
    look = mkComponent "look" {};
    menu = mkComponent "menu" {};
    # panel: ./nwg-panel/hm.nix
    wrapper = mkComponent "wrapper" {};
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
    {
      kdn.hardware.disks.persist."usr/config".files =
        []
        # nwg-drawer pins
        ++ (lib.lists.optional (cfg.drawer.enable) ".cache/nwg-pin-cache");
    }
    (lib.mkIf cfg.displays.enable {
      wayland.windowManager.sway.extraConfig = ''
        include ~/.config/sway/outputs
        include ~/.config/sway/workspaces
      '';
      kdn.hardware.disks.persist."usr/config".files = [
        ".config/nwg-displays/config"
        ".config/sway/outputs"
        ".config/sway/workspaces"
      ];
      wayland.windowManager.sway.config.keybindings = with config.kdn.desktop.sway.keys; {
        "${super}+P" = "exec ${lib.getExe cfg.displays.package}";
      };
    })
  ]);
}

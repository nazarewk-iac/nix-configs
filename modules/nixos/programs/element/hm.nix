{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.matrix;
in {
  options.kdn.programs.matrix = {
    enable = lib.mkEnableOption "element setup";
    element.enable = lib.mkOption {
      type = with lib.types; bool;
      default = true;
    };
    gomuks.enable = lib.mkOption {
      type = with lib.types; bool;
      default = true;
    };
    fluffychat.enable = lib.mkOption {
      type = with lib.types; bool;
      default = false; # TODO: persistence
    };
    nheko.enable = lib.mkOption {
      type = with lib.types; bool;
      default = true;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.element.enable {
      /*
      TODO: try out gomuks https://github.com/tulir/gomuks for better client responsiveness?
      */
      kdn.programs.apps.element-desktop = {
        enable = true;
        package.original = pkgs.element-desktop.override {
          commandLineArgs = "--password-store=gnome-libsecret --disable-gpu";
        };
        dirs.cache = [];
        dirs.config = ["Element"];
        dirs.data = [];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
      };
    })
    (lib.mkIf cfg.gomuks.enable {
      kdn.programs.apps.gomuks = {
        enable = lib.mkDefault false; # this one is old CLI version
        package.original = pkgs.gomuks;
        dirs.cache = ["gomuks"];
        dirs.config = ["gomuks"];
        dirs.data = ["gomuks"];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = ["gomuks"];
      };
      kdn.programs.apps.gomuks-web = {
        enable = lib.mkDefault true;
        package.original = pkgs.gomuks-web;
        dirs.cache = ["gomuks"];
        dirs.config = ["gomuks"];
        dirs.data = ["gomuks"];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = ["gomuks"];
      };
    })
    (lib.mkIf cfg.fluffychat.enable {
      kdn.programs.apps.fluffychat = {
        enable = true;
        package.original = pkgs.fluffychat;
        dirs.cache = [];
        dirs.config = [];
        dirs.data = [];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
      };
    })
    (lib.mkIf cfg.nheko.enable {
      programs.nheko.enable = true;
      kdn.programs.apps.nheko = {
        enable = true;
        package.original = pkgs.nheko;
        dirs.cache = ["nheko"];
        dirs.config = ["nheko"];
        dirs.data = ["nheko"];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
      };
    })
  ]);
}

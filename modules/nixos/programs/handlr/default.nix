{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.handlr;
in {
  options.kdn.programs.handlr = {
    # note: xdg-open forwards to the available resource openers,
    #        but many apps skip xdg-open and use DE integrations directly like: gio open, exo open, kde-open etc.
    # see https://wiki.archlinux.org/title/Xdg-utils#xdg-open
    # see https://wiki.archlinux.org/title/Default_applications
    # see https://unix.stackexchange.com/questions/149033/how-does-linux-choose-which-application-to-open-a-file
    # see https://github.com/chmln/handlr/issues/62
    enable = lib.mkEnableOption "handlr resource opener";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.handlr-regex;
    };
    xdg-utils.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "takes over parts of pkgs.xdg-utils (xdg-open)";
    };
    xdg-utils.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.writeShellApplication {
        name = "xdg-open";
        runtimeInputs = [cfg.package];
        text = ''handlr open "$@"'';
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = with pkgs; [
          cfg.package
        ];

        home-manager.sharedModules = [
          {
            xdg.configFile."handlr/handlr.toml".source = (pkgs.formats.toml {}).generate "handlr.toml" {
              enable_selector = true;
              selector = "${pkgs.wofi}/bin/wofi --dmenu --insensitive --normal-window --prompt='Open With: '";
            };
          }
        ];
      }
      (lib.mkIf cfg.xdg-utils.enable {
        environment.systemPackages = with pkgs; [
          (lib.meta.hiPrio cfg.xdg-utils.package)
        ];
        home-manager.sharedModules = [
          {
            wayland.windowManager.sway.config.keybindings = with config.kdn.desktop.sway.keys;
              builtins.mapAttrs (n: lib.mkDefault) {
                "${super}+O" = "exec ${pkgs.writeScript "xdg-open-clipboard" ''
                  ${lib.getExe cfg.xdg-utils.package} "$(${lib.getExe' pkgs.wl-clipboard "wl-paste"} --no-newline)"
                ''}";
              };
          }
        ];
      })
    ]
  );
}

{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.handlr;
in
{
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
    #glib.enable = lib.mkOption {
    #  type = lib.types.bool;
    #  default = true;
    #  description = "takes over parts of pkgs.glib (Gnome): gio open/launch";
    #};
    #exo.enable = lib.mkOption {
    #  type = lib.types.bool;
    #  default = true;
    #  description = "takes over parts of pkgs.exo (XFCE): exo-open";
    #};
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = with pkgs; [
        cfg.package
      ];
    }
    (lib.mkIf cfg.xdg-utils.enable {
      environment.systemPackages = with pkgs; [
        (lib.meta.hiPrio (pkgs.writeShellApplication {
          name = "xdg-open";
          runtimeInputs = [ cfg.package ];
          text = ''handlr open "$@"'';
        }))
      ];
    })
    #(lib.mkIf cfg.glib.enable {
    #  environment.systemPackages = with pkgs; [
    #    (lib.meta.hiPrio (pkgs.writeShellApplication {
    #      name = "gio";
    #      runtimeInputs = [ cfg.package ];
    #      text = ''
    #        case $1 in
    #          open|launch)
    #            handlr open "$@"
    #            ;;
    #          *)
    #            gio "$@"
    #            ;;
    #        esac
    #      '';
    #    }))
    #  ];
    #})
  ]);
}

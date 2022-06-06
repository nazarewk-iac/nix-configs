{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.programs.gnupg;

  pinentry = pkgs.writeShellApplication {
    name = "pinentry";
    runtimeInputs = with pkgs; [
      pinentry-qt
      pinentry-curses
      pinentry-gtk2
      pinentry-gnome
    ];
    text = builtins.readFile ./pinentry.sh;
  };
in
{
  imports = [
    ./forwarding
  ];

  options.nazarewk.programs.gnupg = {
    enable = mkEnableOption "GnuPG forwarding to remote systems";
  };

  config = mkIf cfg.enable {
    services.pcscd.enable = true;
    programs.gnupg.agent.enable = true;
    programs.gnupg.agent.enableExtraSocket = true;
    programs.gnupg.agent.pinentryFlavor = null;

    home-manager.sharedModules = [
      {
        home.file.".gnupg/gpg-agent.conf".text = ''
          pinentry-program ${pinentry}/bin/pinentry
        '';
      }
    ];

    environment.systemPackages = [
      pinentry
    ];
  };
}

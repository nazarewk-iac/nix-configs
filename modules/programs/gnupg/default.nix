{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.gnupg;

  pinentry =
    let
      python = pkgs.python3;
      runtimeInputs = with pkgs; [
        coreutils
        gnused
        pinentry-curses
        pinentry-qt
      ];
    in
    pkgs.writeScriptBin "pinentry" ''
      #!${python}/bin/python
      import os
      os.environ["PATH"] = f'${lib.makeBinPath runtimeInputs}:os.environ.get("PATH", "")'.strip(os.path.pathsep)
      ${builtins.readFile ./pinentry.py}
    '';
in
{
  options.kdn.programs.gnupg = {
    enable = lib.mkEnableOption "GnuPG forwarding to remote systems";
    pass-secret-service.enable = lib.mkEnableOption "pass-secret-service";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.pcscd.enable = true;
      hardware.gpgSmartcards.enable = true;
      programs.gnupg.agent.enable = true;
      programs.gnupg.agent.enableBrowserSocket = true;
      programs.gnupg.agent.enableExtraSocket = true;
      programs.gnupg.agent.enableSSHSupport = true;
      programs.gnupg.agent.pinentryFlavor = null;

      home-manager.sharedModules = [
        ({ lib, config, ... }: {
          home.activation = {
            linkPasswordStore =
              lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
                #$DRY_RUN_CMD ln -sfT "Nextcloud/drag0nius@nc.nazarewk.pw/important/password-store" "$HOME/.password-store"
              '';
          };
          programs.password-store.enable = true;
          programs.password-store.settings = {
            PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
            PASSWORD_STORE_CLIP_TIME = "10";
          };
          home.file.".gnupg/gpg-agent.conf".text = ''
            pinentry-program ${pinentry}/bin/pinentry
          '';
        })
      ];

      environment.systemPackages = with pkgs; [
        (lib.hiPrio pinentry)
        pinentry-curses
        pinentry-qt

        opensc
        pcsctools

        (pkgs.writeShellApplication {
          name = "pass-pubkeys";
          runtimeInputs = with pkgs; [
            pass
            gnupg
            gawk
          ];
          text = builtins.readFile ./pass-pubkeys.sh;
        })
      ];

      # allow usb-ip access to Yubikeys
      security.polkit.extraConfig = builtins.readFile ./pcsc-lite-rules.js;
    }
    (lib.mkIf cfg.pass-secret-service.enable {
      services.passSecretService.enable = true;
      services.passSecretService.package = pkgs.kdn.pass-secret-service;
      systemd.user.services."dbus-org.freedesktop.secrets" = {
        aliases = [ "pass-secret-service.service" ];
        after = [ "graphical-session-pre.target" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = { Restart = "on-failure"; RestartSec = 1; ExecStartPost = "${pkgs.coreutils}/bin/sleep 2"; };
      };
      environment.systemPackages = with pkgs; [
        libsecret
      ];

      services.gnome.gnome-keyring.enable = lib.mkForce false;
      home-manager.sharedModules = [
        ({ config, ... }: {
          services.gnome-keyring.enable = lib.mkForce false;
        })
      ];
    })
  ]);
}

{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.gnupg;
in
{
  options.kdn.programs.gnupg = {
    enable = lib.mkEnableOption "GnuPG forwarding to remote systems";
    pinentry = lib.mkOption {
      type = lib.types.package;
      default =
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
    };
    pass-secret-service.enable = lib.mkEnableOption "pass-secret-service";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      /*
        low impact workaround to integrate the fix not yet merged to nixos-unstable, see:
        - https://discourse.nixos.org/t/gpg-selecting-card-failed-service-is-not-running/44974/12
        - https://github.com/NixOS/nixpkgs/pull/308884
      */
      programs.gnupg.package = pkgs.gnupg.override {
        pcsclite = pkgs.pcsclite.overrideAttrs (old: {
          postPatch = old.postPatch + (lib.optionalString (!(lib.strings.hasInfix ''--replace-fail "libpcsclite_real.so.1"'' old.postPatch)) ''
            substituteInPlace src/libredirect.c src/spy/libpcscspy.c \
              --replace-fail "libpcsclite_real.so.1" "$lib/lib/libpcsclite_real.so.1"
          '');
        });
      };
    }
    {
      services.pcscd.enable = true;
      hardware.gpgSmartcards.enable = true;
      programs.gnupg.agent.enable = true;
      programs.gnupg.agent.enableBrowserSocket = true;
      programs.gnupg.agent.enableExtraSocket = true;
      # cannot remove keys from the agent and YubiKey GPG is not set up/set up with unknown password
      programs.gnupg.agent.enableSSHSupport = false;
      programs.gnupg.agent.pinentryPackage = cfg.pinentry;

      environment.systemPackages = with pkgs; [
        (lib.hiPrio cfg.pinentry)
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
    (lib.mkIf cfg.pass-secret-service.enable (lib.mkMerge [
      {
        services.passSecretService.enable = true;
        services.passSecretService.package = pkgs.kdn.pass-secret-service;
        systemd.user.services."dbus-org.freedesktop.secrets" = {
          aliases = [ "pass-secret-service.service" ];
          after = [ "graphical-session-pre.target" ];
          partOf = [ "graphical-session.target" ];
          serviceConfig = { Restart = "on-failure"; RestartSec = 1; ExecStartPost = "${pkgs.coreutils}/bin/sleep 2"; };
        };

        services.gnome.gnome-keyring.enable = lib.mkForce false;
        home-manager.sharedModules = [{ services.gnome-keyring.enable = lib.mkForce false; }];
      }
      (lib.mkIf config.kdn.desktop.sway.enable {
        systemd.user.services."dbus-org.freedesktop.secrets" = {
          requires = [ config.kdn.desktop.sway.systemd.envs.target ];
          after = [ config.kdn.desktop.sway.systemd.envs.target ];
        };
      })
    ]))
  ]);
}

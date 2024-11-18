{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.gnupg;
in {
  options.kdn.programs.gnupg = {
    enable = lib.mkEnableOption "GnuPG forwarding to remote systems";
    pinentry = lib.mkOption {
      type = lib.types.package;
      default = pkgs.kdn.pinentry;
    };
    pass-secret-service.enable = lib.mkEnableOption "pass-secret-service";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
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
        (lib.lowPrio pinentry-all)

        opensc
        pcsctools

        (pkgs.writeShellApplication {
          name = "pass-pubkeys";
          runtimeInputs = with pkgs; [pass gnupg gawk];
          text = builtins.readFile ./pass-pubkeys.sh;
        })

        pkgs.kdn.gpg-smartcard-reset-keys
      ];

      # allow usb-ip access to Yubikeys
      security.polkit.extraConfig = builtins.readFile ./pcsc-lite-rules.js;
    }
    {
      home-manager.sharedModules = [
        (hm: {
          programs.gpg.enable = true;
          home.persistence."usr/data".directories = [".gnupg"];
          home.persistence."usr/config".directories = [".config/pinentry-kdn"];
          systemd.user.tmpfiles.rules = [
            "d ${hm.config.home.homeDirectory}/.gnupg 0700 - - -"
            "d ${hm.config.home.homeDirectory}/.config/pinentry-kdn 0700 - - -"
          ];
        })
      ];
    }
    (lib.mkIf cfg.pass-secret-service.enable (lib.mkMerge [
      {
        services.passSecretService.enable = true;
        services.passSecretService.package = pkgs.kdn.pass-secret-service;
        systemd.user.services."dbus-org.freedesktop.secrets" = {
          aliases = ["pass-secret-service.service"];
          after = ["graphical-session-pre.target"];
          partOf = ["graphical-session.target"];
          serviceConfig = {
            Restart = "on-failure";
            RestartSec = 1;
            ExecStartPost = "${pkgs.coreutils}/bin/sleep 2";
          };
        };

        services.gnome.gnome-keyring.enable = lib.mkForce false;
        home-manager.sharedModules = [{services.gnome-keyring.enable = lib.mkForce false;}];
      }
      (lib.mkIf config.kdn.desktop.sway.enable {
        systemd.user.services."dbus-org.freedesktop.secrets" = {
          requires = [config.kdn.desktop.sway.systemd.envs.target];
          after = [config.kdn.desktop.sway.systemd.envs.target];
        };
      })
    ]))
    {
      systemd.user.services."gpg-agent" = {
        after = ["paths.target"];
        serviceConfig.Slice = "background.slice";
        postStart = ''
          ${lib.getExe pkgs.kdn.gpg-smartcard-reset-keys}
        '';
      };
    }
  ]);
}

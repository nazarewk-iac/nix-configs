{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.gnupg;

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
  options.kdn.programs.gnupg = {
    enable = lib.mkEnableOption "GnuPG forwarding to remote systems";
    pass-secret-service.enable = lib.mkEnableOption "pass-secret-service";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.pcscd.enable = true;
      programs.gnupg.agent.enable = true;
      programs.gnupg.agent.enableExtraSocket = true;
      programs.gnupg.agent.pinentryFlavor = null;

      home-manager.sharedModules = [
        {
          programs.password-store.enable = true;
          programs.password-store.settings = {
            # for Android interoperability, see https://github.com/drduh/YubiKey-Guide/issues/152#issuecomment-852176877
            PASSWORD_STORE_GPG_OPTS = "--no-throw-keyids";
          };
          home.file.".gnupg/gpg-agent.conf".text = ''
            pinentry-program ${pinentry}/bin/pinentry
          '';
        }
      ];

      environment.systemPackages = with pkgs; [
        pinentry
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
      environment.systemPackages = with pkgs; [
        libsecret
      ];

      programs.ssh.startAgent = true;

      services.gnome.gnome-keyring.enable = lib.mkForce false;
      home-manager.sharedModules = [
        ({ config, ... }: {
          services.gnome-keyring.enable = lib.mkForce false;
          # copied from HM config
          systemd.user.services.pass-secret-service = {
            Unit = {
              Description = "Pass libsecret service";
              Requires = [ "kdn-sway-envs.target" ];
              After = [ "kdn-sway-envs.target" ];
            };
            Install.WantedBy = [ "kdn-sway-envs.target" ];
            Service = {
              # pass-secret-service doesn't use environment variables for some reason.
              ExecStart =
                "${pkgs.kdn.pass-secret-service}/bin/pass_secret_service --path ${config.programs.password-store.settings.PASSWORD_STORE_DIR}";
              ExecStartPost = "${pkgs.coreutils}/bin/sleep 2";
            };
          };
        })
      ];
    })
  ]);
}

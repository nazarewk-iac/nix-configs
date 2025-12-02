{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}: {
  imports = [
    kdnConfig.self.nixosModules.default
  ];

  config = lib.mkMerge [
    {
      /*
      `image.baseName` gives a stable image filename
      - see https://github.com/NixOS/nixpkgs/blob/30a61f056ac492e3b7cdcb69c1e6abdcf00e39cf/nixos/modules/image/file-options.nix#L9-L16
      */
      image.baseName = lib.mkForce "kdn-nixos-install-iso";

      /*
       `install-iso` uses some weird GRUB booting chimera
      see https://github.com/NixOS/nixpkgs/blob/9fbeebcc35c2fbc9a3fb96797cced9ea93436097/nixos/modules/installer/cd-dvd/iso-image.nix#L780-L787
      */
      boot.initrd.systemd.enable = lib.mkForce false;
      boot.loader.systemd-boot.enable = lib.mkForce false;
    }
    {
      kdn.hostName = "kdn-nixos-install-iso";
      home-manager.sharedModules = [{home.stateVersion = "26.05";}];
      kdn.security.secrets.allow = true;
      kdn.profile.machine.baseline.enable = true;
      kdn.security.disk-encryption.enable = true;
      kdn.networking.netbird.clients.priv.type = "ephemeral";

      environment.systemPackages = with pkgs; [
      ];
    }
    {
      users.users.root.openssh.authorizedKeys.keys = config.users.users.kdn.openssh.authorizedKeys.keys;
    }
    {
      environment.etc."NetworkManager/conf.d/98-kdn-unmanage-ethernet.conf".text = ''
        [device-unmanage-ethernet]
        match-device=interface-name:enp*
        managed=0
      '';

      systemd.services.kdn-nm-enable-single-ethernet = {
        description = "Setup Single Managed Ethernet Interface";
        before = ["NetworkManager.service" "network-pre.target"];
        wants = ["network-pre.target"];
        wantedBy = ["NetworkManager.service"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutSec = 15;
          ExecStart = lib.getExe (pkgs.writeShellApplication {
            name = "kdn-nm-enable-single-ethernet";
            runtimeEnv.config_file = "/etc/NetworkManager/conf.d/99-manage-first-ethernet.conf";
            runtimeInputs = with pkgs; [
              bash
              coreutils
              systemd
            ];
            text = builtins.readFile ./kdn-nm-enable-single-ethernet.sh;
          });
        };
      };
    }
  ];
}

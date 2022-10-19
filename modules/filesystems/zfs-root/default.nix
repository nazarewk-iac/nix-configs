{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.filesystems.zfs-root;
in
{
  options.kdn.filesystems.zfs-root = {
    enable = lib.mkEnableOption "ZFS setup";

    sshUnlock = {
      enable = lib.mkEnableOption "ZFS unlocking over SSH setup";
      authorizedKeys = mkOption {
        type = types.listOf types.str;
        default = config.users.users.nazarewk.openssh.authorizedKeys.keys;
      };
      hostKeys = mkOption {
        type = types.listOf (types.either types.str types.path);
        default = [
          # sudo mkdir -p /boot/nazarewk-ssh
          # sudo ssh-keygen -t rsa -N "" -f /boot/nazarewk-ssh/ssh_host_rsa_key
          # sudo ssh-keygen -t ed25519 -N "" -f /boot/nazarewk-ssh/ssh_host_ed25519_key
          /boot/nazarewk-ssh/ssh_host_rsa_key
          /boot/nazarewk-ssh/ssh_host_ed25519_key
        ];
      };
      secrets = mkOption {
        default = { };
        type = types.attrsOf (types.nullOr types.path);
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      boot.kernelPackages = pkgs.zfs.latestCompatibleLinuxPackages;
      boot.loader.grub.copyKernels = true;
      boot.kernelParams = [ "nohibernate" ];
      boot.initrd.supportedFilesystems = [ "zfs" ];
      boot.supportedFilesystems = [ "zfs" ];
      boot.zfs.enableUnstable = true;

      services.zfs.autoScrub.enable = true;
      services.zfs.autoSnapshot.enable = true;
      services.zfs.autoSnapshot.flags = "-k -p --utc";
      services.zfs.autoSnapshot.frequent = 12;
      services.zfs.autoSnapshot.daily = 7;
      services.zfs.autoSnapshot.weekly = 6;
      services.zfs.autoSnapshot.monthly = 1;
      services.zfs.trim.enable = true;

      environment.systemPackages = with pkgs; [
        zfs-prune-snapshots
      ];

      virtualisation.docker.storageDriver = "zfs";
    }
    (mkIf cfg.sshUnlock.enable {
      # see https://nixos.wiki/wiki/ZFS#Unlock_encrypted_zfs_via_ssh_on_boot
      boot.kernelParams = [ "ip=dhcp" ];
      boot.initrd.secrets = cfg.sshUnlock.secrets;
      boot.initrd.network.enable = true;
      boot.initrd.network.ssh.enable = true;
      boot.initrd.network.ssh.port = 9022;
      boot.initrd.network.ssh.authorizedKeys = cfg.sshUnlock.authorizedKeys;
      boot.initrd.network.ssh.hostKeys = cfg.sshUnlock.hostKeys;
      boot.initrd.network.postCommands = ''
        cat <<EOF > /root/.profile
        if pgrep -x "zfs" > /dev/null
        then
          zfs load-key -a
          killall zfs
        else
          echo "zfs not running -- maybe the pool is taking some time to load for some unforseen reason."
        fi
        EOF
      '';
    })
  ]);
}

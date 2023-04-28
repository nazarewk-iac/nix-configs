{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.filesystems.zfs-root;
in
{
  options.kdn.filesystems.zfs-root = {
    enable = lib.mkEnableOption "ZFS setup";

    sshUnlock = {
      # Note: this does not work with systemd stage 0
      enable = lib.mkEnableOption "ZFS unlocking over SSH setup";
      authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = config.users.users.kdn.openssh.authorizedKeys.keys;
      };
      hostKeys = lib.mkOption {
        type = lib.types.listOf (lib.types.either lib.types.str lib.types.path);
        default = [
          # sudo mkdir -p /boot/nazarewk-ssh
          # sudo ssh-keygen -t rsa -N "" -f /boot/nazarewk-ssh/ssh_host_rsa_key
          # sudo ssh-keygen -t ed25519 -N "" -f /boot/nazarewk-ssh/ssh_host_ed25519_key
          /boot/nazarewk-ssh/ssh_host_rsa_key
          /boot/nazarewk-ssh/ssh_host_ed25519_key
        ];
      };
      secrets = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (lib.types.nullOr lib.types.path);
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.filesystems.zfs.enable = true;
    }
    (lib.mkIf cfg.sshUnlock.enable {
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

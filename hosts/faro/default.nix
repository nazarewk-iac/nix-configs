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
      kdn.hostName = "faro";

      system.stateVersion = "25.05";
      home-manager.sharedModules = [{home.stateVersion = "25.05";}];
      networking.hostId = "4b2dd30f"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      kdn.profile.hardware.darwin-utm-guest.enable = true;
      kdn.profile.machine.baseline.enable = true;
      security.sudo.wheelNeedsPassword = false;
    }
    {
      kdn.disks.initrd.failureTarget = "rescue.target";
      kdn.disks.enable = true;
      kdn.disks.devices."boot".path = "/dev/vda";
      kdn.disks.zpools."${config.kdn.disks.zpool-main.name}".import.timeout = 300;
      ## replaced by `ext-*-faro` *.img backed disks
      #kdn.disks.luks.volumes."virtual-faro" = {
      #  targetSpec.path = "/dev/vdb";
      #  uuid = "4b50067d-05c4-46eb-a1e1-e0a9c6106559";
      #  headerSpec.partNum = 2;
      #};
      kdn.disks.luks.volumes."ext-01-faro" = {
        /*
        pass generate "luks/ext-01-faro/passphrase" 32
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$(pass show "luks/ext-01-faro/passphrase" | tr -d '\n' | psub)" "faro.lan.etra.net.int.kdn.im.:/tmp/ext-01-faro.passphrase"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." ln -sfT /tmp/ext-01-faro.passphrase /tmp/ext-01-faro.key
        # pulled from result of `./disko-build-scripts.sh faro`
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo sgdisk --align-end --set-alignment=512 --new=3:0:+32M --partition-guid="3:R" --change-name="3:ext-01-faro-header" --typecode=3:0FC63DAF-8483-4772-8E79-3D69D8477DE4 "/dev/vda"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo partx -u /dev/vda
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo cryptsetup -q luksFormat "/dev/disk/by-id/virtio-30F4989DAE95B60F797D" --uuid=30f4989d-dcc0-483b-b1c1-ae95b60f797d --header="/dev/disk/by-partlabel/ext-01-faro-header" --key-file=/tmp/ext-01-faro.key
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo cryptsetup open "/dev/disk/by-id/virtio-30F4989DAE95B60F797D" "ext-01-faro-crypted" --header="/dev/disk/by-partlabel/ext-01-faro-header" --key-file=/tmp/ext-01-faro.key --persistent
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo systemd-cryptenroll --unlock-key-file="/tmp/ext-01-faro.key" --tpm2-device=auto "/dev/disk/by-partlabel/ext-01-faro-header"
        # TODO: backup header
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo cryptsetup luksHeaderBackup "/dev/disk/by-partlabel/ext-01-faro-header" --header-backup-file="/tmp/luks-ext-01-faro-header.bin"
        */
        targetSpec.path = "/dev/disk/by-id/virtio-30F4989DAE95B60F797D";
        uuid = "30f4989d-dcc0-483b-b1c1-ae95b60f797d";
        headerSpec.partNum = 3;
      };
      kdn.disks.luks.volumes."ext-02-faro" = {
        /*
        pass generate "luks/ext-02-faro/passphrase" 32
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$(pass show "luks/ext-02-faro/passphrase" | tr -d '\n' | psub)" "faro.lan.etra.net.int.kdn.im.:/tmp/ext-02-faro.passphrase"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." ln -sfT /tmp/ext-02-faro.passphrase /tmp/ext-02-faro.key
        # pulled from result of `./disko-build-scripts.sh faro`
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo sgdisk --align-end --set-alignment=512 --new=4:0:+32M --partition-guid="4:R" --change-name="4:ext-02-faro-header" --typecode=4:FC63DAF-8483-4772-8E79-3D69D8477DE4 "/dev/vda"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo partx -u /dev/vda
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo cryptsetup -q luksFormat "/dev/disk/by-id/virtio-4F4152F6B04223FF41F8" --uuid="4f4152f6-5098-4a1a-9c2d-b04223ff41f8" --header="/dev/disk/by-partlabel/ext-02-faro-header" --key-file=/tmp/ext-02-faro.key
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo cryptsetup open "/dev/disk/by-id/virtio-4F4152F6B04223FF41F8" "ext-02-faro-crypted" --header="/dev/disk/by-partlabel/ext-02-faro-header" --key-file=/tmp/ext-02-faro.key --persistent
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo systemd-cryptenroll --unlock-key-file="/tmp/ext-02-faro.key" --tpm2-device=auto "/dev/disk/by-partlabel/ext-02-faro-header"
        # TODO: backup header
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo cryptsetup luksHeaderBackup "/dev/disk/by-partlabel/ext-02-faro-header" --header-backup-file="/tmp/luks-ext-02-faro-header.bin"
        */
        targetSpec.path = "/dev/disk/by-id/virtio-4F4152F6B04223FF41F8";
        uuid = "4f4152f6-5098-4a1a-9c2d-b04223ff41f8";
        headerSpec.partNum = 4;
      };
      /*
      Migrating to new set of `ext-*` disks:
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo zpool replace faro-main /dev/disk/by-id/dm-uuid-CRYPT-LUKS2-4b50067d05c446eba1e1e0a9c6106559-virtual-faro-crypted /dev/disk/by-id/dm-uuid-CRYPT-LUKS2-30f4989ddcc0483bb1c1ae95b60f797d-ext-01-faro-crypted
        # wait for resilvering to finish
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo zpool attach faro-main /dev/disk/by-id/dm-uuid-CRYPT-LUKS2-30f4989ddcc0483bb1c1ae95b60f797d-ext-01-faro-crypted /dev/disk/by-id/dm-uuid-CRYPT-LUKS2-4f4152f650984a1a9c2db04223ff41f8-ext-02-faro-crypted
        # wait for resilvering to finish
        # expand the drive
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "faro.lan.etra.net.int.kdn.im." sudo zpool online -e faro-main /dev/disk/by-id/dm-uuid-CRYPT-LUKS2-30f4989ddcc0483bb1c1ae95b60f797d-ext-01-faro-crypted /dev/disk/by-id/dm-uuid-CRYPT-LUKS2-4f4152f650984a1a9c2db04223ff41f8-ext-02-faro-crypted
      */
    }
  ];
}

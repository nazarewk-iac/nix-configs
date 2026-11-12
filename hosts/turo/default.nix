/*
  OFFLINE as of 2026-11-12 — none of the SSH-CA work below has been applied to the running host.

  Since this host was last switched, the fleet moved SSH host keys out of the sops-nix boot path:

    * the managed host key is the only sshd identity AND the host's SOPS age identity,
      deployed out of band to /etc/ssh/ssh_host_ed25519_key by
      `kdnctl host ensure ssh-host-keys`, and preserved across reboots;
    * `hosts/<host>/ssh-keys/` holds that key encrypted to the two unattended YubiKeys only —
      a host must not be able to decrypt its own identity;
    * the installer-generated rsa, ed25519 and mldsa44 keys are no longer in
      `services.openssh.hostKeys`;
    * every `ssh-<host>` anchor in `.sops.yaml` names the managed key, and the certificates are
      signed by the fleet CA and trusted through `@cert-authority`.

  This host is outside that story: it declares no `kdn.certificates.certs` leaf, has no
  `ssh-host` certificate, no pin in `ssh_known_hosts`, and its key exists only in the local,
  uncommitted `secrets/hosts/turo/ssh-keys/`. The symlinks that used to expose it under
  `hosts/turo/ssh-keys/` were removed on 2026-11-12, because they dangled for anyone without
  that local store.

  To bring it up to date, decide first whether it joins the CA fleet. If it does:

    1. add `kdn.certificates.certs.ssh-host-turo` with its principals, mirroring
       `hosts/briv/default.nix`;
    2. run `kdnctl host -n turo ensure ssh-host-keys --upload` to write the key to the host;
    3. re-anchor `ssh-turo` in `.sops.yaml` to the managed key's age form and run
       `sops updatekeys` on every file that lists the old one;
    4. build, switch, and verify with a strict `ssh turo true`.

  Until then it keeps decrypting `*.unattended.sops.*` with the installer key its anchor still
  names.
*/
{
  config,
  lib,
  kdnConfig,
  ...
}:
{
  imports = [
    kdnConfig.self.nixosModules.default
  ];

  config = lib.mkMerge [
    {
      kdn.hostName = "turo";

      system.stateVersion = "26.05";
      home-manager.sharedModules = [ { home.stateVersion = "26.05"; } ];
      networking.hostId = "0f4fc33f"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      kdn.profile.machine.baseline.enable = true;
      kdn.hw.cpu.intel.enable = true;
      security.sudo.wheelNeedsPassword = false;

      zramSwap.enable = false;

      boot.tmp.tmpfsSize = "4G";
      boot.initrd.kernelModules = [
        "sdhci"
        "sdhci_pci"
      ];
    }
    {
      kdn.services.k8s.enable = true;
      kdn.services.k8s.kubeadm.enable = true;

      kdn.networking.enable = true;
      kdn.networking.iface.default = "lan";
      kdn.networking.iface.internal = "pic";

      kdn.networking.ifaces."kdn-eth0".selector.mac = "a8:b8:e0:04:13:0d";
      kdn.networking.ifaces."kdn-eth1".selector.mac = "a8:b8:e0:04:13:0e";
      kdn.networking.ifaces."kdn-eth2".selector.mac = "a8:b8:e0:04:13:0f";
      kdn.networking.ifaces."kdn-eth3".selector.mac = "a8:b8:e0:04:13:10";

      kdn.networking.bonds."lan".type = "lacp";
      kdn.networking.bonds."lan".children = [
        "kdn-eth0"
        "kdn-eth1"
        "kdn-eth2"
        "kdn-eth3"
      ];
      kdn.networking.ifaces."lan".mac = "ce:bf:21:34:fa:e1";
      kdn.networking.ifaces."lan".dynamicIPClient = true;
      kdn.networking.ifaces."lan".metric = 100;

      kdn.networking.vlans."pic".id = 1859;
      kdn.networking.vlans."pic".parent = "lan";
      kdn.networking.ifaces."pic".dynamicIPClient = true;
      kdn.networking.ifaces."pic".metric = 1000;
      kdn.networking.ifaces."pic".address.internal4 = "10.92.0.9/24";
      kdn.networking.ifaces."pic".address.internal6 = "fd12:ed4e:366d:eb17:501c:1781:1f79:5ccb/64";
    }
    {
      kdn.disks.enable = true;

      # 250GB for system disk - /dev/disk/by-id/nvme-eui.002538d341a07655
      kdn.disks.devices."${config.kdn.disks.defaults.bootDeviceName}".path =
        "/dev/disk/by-id/nvme-eui.002538d341a07652";
      kdn.disks.luks.volumes."system-turo" = {
        uuid = "ef38c899-33de-4c41-9c74-bad311c2b293";
        target.deviceKey = config.kdn.disks.defaults.bootDeviceName;
        target.partitionKey = "system-turo";
        targetSpec.size = "100%";
        targetSpec.partNum = 3;
        headerSpec.partNum = 2;
      };

      disko.devices.zpool."${config.kdn.disks.zpool-main.name}" = {
        datasets."luks/data-turo/header" = {
          type = "zfs_volume";
          options."com.sun:auto-snapshot" = "true";
          extraArgs = [ "-p" ]; # create parents, this is missing from the volume
          size = lib.mkDefault "${toString config.kdn.disks.luks.header.size}M";
        };
      };

      # 1 TB high durability disk - /dev/disk/by-id/nvme-eui.002538b631a43842
      kdn.disks.luks.volumes."data-turo" = {
        uuid = "29814ef8-632e-4c37-a1b8-541eecb45488";
        targetSpec.path = "/dev/disk/by-id/nvme-eui.002538b631a43842";
        header.path = "/dev/zvol/${config.kdn.disks.zpool-main.name}/luks/data-turo/header";
        header.deviceKey = null;
        header.partitionKey = null;
        zpool.name = "pic-local";
      };
      kdn.disks.zpools."pic-local" = { };
    }
    {
      kdn.disks.disko.devices._meta.deviceDependencies = {
        disk.data-turo = [
          [
            "zpool"
            config.kdn.disks.zpool-main.name
          ]
        ];
      };
    }
  ];
}

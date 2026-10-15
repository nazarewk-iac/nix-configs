{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}:
{
  imports = [
    kdnConfig.self.nixosModules.default
    "${kdnConfig.self}/data/ca/ca-dag.nix"
    {
      imports = kdnConfig.self.denLib.imports {
        class = "nixos";
        aspects = [
          "ca-dag"
          "certificates"
          "ssh-ca"
        ];
      };
    }
  ];

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = kdnConfig.features.rpi4;
          message = "requires Raspberry Pi 4 profile.";
        }
        {
          assertion = !(kdnConfig.features.rpi4 && kdnConfig.features.installer);
          message = "cannot use Raspberry Pi 4 installer profile.";
        }
      ];
    }
    {
      kdn.hostName = "briv";

      system.stateVersion = "25.05";
      home-manager.sharedModules = [ { home.stateVersion = "25.05"; } ];
      networking.hostId = "b86e74e8"; # cut -c-8 </proc/sys/kernel/random/uuid

      # A headless Raspberry Pi 4. Remove documentation and diagnostic tooling.
      kdn.minimalServer = true;
    }
    {
      kdn.profile.machine.baseline.enable = true;
      security.sudo.wheelNeedsPassword = false;
    }
    {
      kdn.services.home-assistant.enable = true;
      kdn.services.home-assistant.zha.enable = true;
      kdn.services.home-assistant.tuya-cloud.enable = true;
      kdn.services.home-assistant.tuya-local.enable = true;
    }
    {
      kdn.profile.hardware.rpi4.hat.ups.enable = true;
      kdn.profile.hardware.rpi4.hat.fan.enable = true;
    }
    (lib.mkIf false {
      # TODO: enable disk management
      # TODO: those are unlocked automatically using TPM2, switch to etra (or k8s cluster) backed Clevis+Tang unlock
      kdn.disks.enable = true;
      kdn.disks.devices."boot".path = "/dev/disk/by-id/mmc-JC1S5_0x2a7357a9-part1";
      kdn.disks.luks.volumes."vp4300-briv" = {
        targetSpec.path = "/dev/disk/by-id/nvme-nvme.1e4b-5650343330304c45444242323333343032303433-5669706572205650343330304c20325442-00000001";
        uuid = "4d9ecf11-98c4-4cfa-b223-d4dceef00dc4";
        headerSpec.partNum = 2;
      };

      kdn.disks.luks.volumes."px500-briv" = {
        targetSpec.path = "/dev/disk/by-id/ata-SSDPR-PX500-512-80-G2_2Z0112153";
        uuid = "c9a44d27-fd7e-40ea-8029-5e66cafc2960";
        headerSpec.partNum = 3;
      };
    })
    # TODO: I had to `mkdir /var/tmp/nix-daemon` to finish the build
    {
      # kdn.nix.remote-builder.localhost.publicHostKey = "??";
      kdn.nix.remote-builder.localhost.maxJobs = 2;
      kdn.nix.remote-builder.localhost.speedFactor = 4;
    }
    {
      # The SSH host certificate. `principals` names the short name (checked by the
      # `kdn-*` dispatcher through `HostKeyAlias`) and each FQDN a client may use.
      kdn.certificates.repoRoot = kdnConfig.self;
      kdn.certificates.certs.ssh-host-briv = {
        ca = "kdn";
        type = "ssh-host";
        commonName = "briv";
        principals = [
          "briv"
          "briv.lan.etra.net.int.kdn.im"
          "briv.priv.nb.net.int.kdn.im"
          "briv.netbird.cloud"
        ];
        directory = "hosts/briv/certs";
        certFile = "ssh_host_ed25519-cert.pub";
        keyFile = "ssh_host_ed25519.key";
        keySource = "managed";
      };
    }
  ];
}

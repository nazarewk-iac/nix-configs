# pryll, the mother's desktop, on the den tree. FULL carryover of `hosts/pryll/` (old universal
# tree), with no `modules/universal` reference on this host's path.
#
# The output is `denConfigurations.pryll`; never add this host to `nixosConfigurations`.
#
# Measured facts (live machine, 2026-10-30):
#   - ESP and the detached LUKS header are on the 28.9 G Lexar USB stick
#   - the root ZFS pool is on the internal HS-SSD-E100 256G (serial 30023586951), LUKS uuid
#     4f314bc3-6c3c-4a37-9756-5a03d286cf7b, header on partition 2
#   - the machine can be reformatted; nothing on it must be preserved across a reinstall
#
# Unlock target was TPM2-only, but the machine's TPM is 1.2 (`tpm_version_major = 1`) and
# systemd-cryptenroll cannot use it. Unlock stays FIDO2 (YubiKey tap) or the pass keyfile
# (keyslot 1) until a TPM 2.0 is available. See run book phase 2b.
#
# The body stays an INLINE attrset here: a module in this entity's own `nixos` aspect cannot
# request `pkgs` (it recurses through `_module.args`). `lib` and `inputs` come from the closure.
{ kdn, inputs, lib, ... }:
let
  bootDevicePath = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04KE345HX9EUZLSW-0:0";
  rootDiskPath = "/dev/disk/by-id/ata-HS-SSD-E100_256G_30023586951";
  rootLuksUuid = "4f314bc3-6c3c-4a37-9756-5a03d286cf7b";
  # rustdesk is marked unfree; instantiate nixpkgs with it allowed just for this package.
  rustdesk = (import inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
  }).rustdesk;
in
{
  den.hosts.x86_64-linux.pryll.class = "nixos";

  den.aspects.pryll.includes = with kdn; [
    # hardware
    hw-basic
    hw-cpu-intel
    hw-gpu-intel
    hw-nanokvm
    # base
    locale
    nix-config
    nix-remote-builder
    secrets
    # accounts + home manager
    user
    hm-bootstrap
    # desktop
    profile-desktop
    desktop-kde
    stylix
    # disks / impermanence (`disks` alone: it asserts mutual exclusion with `fs-luks-zfs` and
    # generates the whole LUKS+ZFS layout and preservation)
    disks
    disks-persist
    # host certificate
    ssh-ca
  ];

  den.aspects.pryll.nixos = {
    imports = [ inputs.home-manager.nixosModules.home-manager ];

    kdn.hostName = "pryll";

    # Let the initrd emergency shell accept root (same hash). A failed LUKS prompt then drops
    # to a usable shell instead of locking the machine out entirely.
    kdn.profile-baseline.initrd.emergencyAccess = "$y$j9T$AhbnpYZawNWNGfuq1h9/p0$jmitwtZwTr72nBgvg2TEmrGmhRR30sQ.hQ7NZk1NqJD";
    networking.hostName = "pryll";
    networking.hostId = "25880d1d";
    system.stateVersion = "26.05";
    home-manager.useGlobalPkgs = true;
    home-manager.sharedModules = [ { home.stateVersion = "26.05"; } ];

    security.sudo.wheelNeedsPassword = false;

    # profile-baseline sets users.mutableUsers = false, tripping the "locked out" assert (bn is
    # not wheel and no hash is in the repo). Allow `passwd`; autologin makes it a formality.
    users.mutableUsers = lib.mkForce true;

    # Root login for the emergency/rescue shell. Without it a failed LUKS prompt drops to
    # emergency mode with no way in (gen 33 failed this way once). The hash is the same
    # yescrypt value the old universal tree ships, so the emergency password is unchanged.
    users.users.root.hashedPassword = "$y$j9T$AhbnpYZawNWNGfuq1h9/p0$jmitwtZwTr72nBgvg2TEmrGmhRR30sQ.hQ7NZk1NqJD";

    # The one account: the mother.
    kdn.users.bn = {
      uid = 27748;
      fullName = "Beata";
      extraGroups = [
        "audio" "dialout" "lp" "lpadmin" "mlocate" "networkmanager"
        "pipewire" "plugdev" "power" "scanner" "tty" "video"
      ];
    };

    # KDE Plasma 6, SDDM autologin into Plasma as bn.
    services.displayManager.sddm.settings.Autologin = {
      Session = "plasma.desktop";
      User = "bn";
    };

    # Wallpaper defect: the stylix KDE target was disabled for root and kdn but not bn, so the
    # wallpaper step failed and the old host restarted `home-manager-bn`. Disable it for bn too.
    home-manager.users.bn.stylix.targets.kde.enable = false;

    # Remote support: RustDesk client (not TeamViewer; no server aspect here). Unattended access
    # is set up once over the KVM (fixed password + relay). See run book phase 5.
    environment.systemPackages = [ rustdesk ];
    systemd.services.rustdesk = {
      description = "RustDesk unattended client";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${rustdesk}/bin/rustdesk --service";
        Restart = "always";
        RestartSec = 5;
      };
    };

    # EFI machine (UEFI 2.31, Secure Boot off): systemd-boot, not grub.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = false;
    boot.loader.grub.enable = false;

    # Disks: detached-header LUKS on the internal SSD, header and ESP on the USB stick.
    kdn.disks.devices."boot".path = bootDevicePath;
    kdn.disks.luks.volumes."hs-e100-pryll" = {
      targetSpec.path = rootDiskPath;
      uuid = rootLuksUuid;
      headerSpec.partNum = 2;
    };
  };
}

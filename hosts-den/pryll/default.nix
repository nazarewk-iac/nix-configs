# pryll, the mother's desktop, on the den tree. FULL carryover of `hosts/pryll/` (old universal
# tree), with no `modules/universal` reference on this host's path.
#
# The output is `denConfigurations.pryll`; never add this host to `nixosConfigurations`.
#
# Measured facts (live machine, 2026-10-30) used below:
#   - ESP and the detached LUKS header are on the 28.9 G Lexar USB stick
#   - the root ZFS pool is on the internal HS-SSD-E100 256G (serial 30023586951), LUKS uuid
#     4f314bc3-6c3c-4a37-9756-5a03d286cf7b, header on partition 2
#   - the machine can be reformatted; nothing on it must be preserved across a reinstall
#
# Unlock is TPM2-only by owner decision (no YubiKey at boot). Enrolment is a runtime step
# (`systemd-cryptenroll --tpm2-device=auto`), recorded in the run book, not here.
{ kdn, inputs, lib, ... }:
let
  bootDevicePath = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04KE345HX9EUZLSW-0:0";
  rootDiskPath = "/dev/disk/by-id/ata-HS-SSD-E100_256G_30023586951";
  rootLuksUuid = "4f314bc3-6c3c-4a37-9756-5a03d286cf7b";
in
{
  den.hosts.x86_64-linux.pryll.class = "nixos";

  den.aspects.pryll.includes = with kdn; [
    # hardware
    hw-basic
    hw-cpu-intel
    hw-gpu-intel
    hw-nanokvm
    hw-yubikey
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
    # disks / impermanence (include `disks` only: it asserts mutual exclusion with `fs-luks-zfs`
    # and generates the whole LUKS+ZFS layout and preservation itself)
    disks
    disks-persist
    # remote support and host certificate
    ssh-ca
    service-rustdesk
  ];

  den.aspects.pryll.nixos = {
    imports = [ inputs.home-manager.nixosModules.home-manager ];

    kdn.hostName = "pryll";
    networking.hostName = "pryll";
    networking.hostId = "25880d1d";
    system.stateVersion = "26.05";
    home-manager.useGlobalPkgs = true;
    home-manager.sharedModules = [ { home.stateVersion = "26.05"; } ];

    security.sudo.wheelNeedsPassword = false;

    # profile-baseline sets users.mutableUsers = false, which trips the "locked out" assert
    # (bn is not in wheel and no hash is in the repo). Allow the owner to set passwords with
    # `passwd`; autologin means the password is a formality.
    users.mutableUsers = lib.mkForce true;

    # The one account: the mother.
    kdn.users.bn = {
      uid = 27748;
      fullName = "Beata";
      extraGroups = [
        "audio"
        "dialout"
        "lp"
        "lpadmin"
        "mlocate"
        "networkmanager"
        "pipewire"
        "plugdev"
        "power"
        "scanner"
        "tty"
        "video"
      ];
    };

    # KDE Plasma 6, SDDM autologin into Plasma as bn.
    services.displayManager.sddm.settings.Autologin = {
      Session = "plasma.desktop";
      User = "bn";
    };

    # The wallpaper defect of the old tree: the stylix KDE target is disabled for root and kdn
    # but not for bn, so the wallpaper step fails and the old host restarts `home-manager-bn`.
    # Disable it for bn too; Plasma keeps its stock wallpaper and the unit succeeds first try.
    home-manager.users.bn.stylix.targets.kde.enable = false;

    # Remote support: TeamViewer, as the old host used. RustDesk is the alternative in the run book.
    services.teamviewer.enable = true;

    # EFI machine (UEFI 2.31, Secure Boot off): systemd-boot, not grub.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = false;
    boot.loader.grub.enable = false;

    # Disks: the detached-header LUKS volume on the internal SSD, header and ESP on the USB stick.
    kdn.disks.devices."boot".path = bootDevicePath;
    kdn.disks.luks.volumes."hs-e100-pryll" = {
      targetSpec.path = rootDiskPath;
      uuid = rootLuksUuid;
      headerSpec.partNum = 2;
    };
  };
}

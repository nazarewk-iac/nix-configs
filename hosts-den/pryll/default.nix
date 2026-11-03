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
{
  kdn,
  inputs,
  lib,
  ...
}:
let
  bootDevicePath = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04KE345HX9EUZLSW-0:0";
  rootDiskPath = "/dev/disk/by-id/ata-HS-SSD-E100_256G_30023586951";
  rootLuksUuid = "4f314bc3-6c3c-4a37-9756-5a03d286cf7b";
  # rustdesk is marked unfree; instantiate nixpkgs with it allowed for this host's packages.
  hostPkgs = import inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
  rustdesk = hostPkgs.rustdesk;
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
    # account profiles from data/users.data.nix
    user-profiles
  ];

  den.aspects.pryll.nixos = {
    imports = [
      # The fleet root CA node (`kdn.ca-dag.cas.kdn`, `ssh = true`). The `ssh-ca` aspect reads it
      # to derive the CA public key for `TrustedUserCAKeys` and the `@cert-authority` line.
      ../../data/ca/ca-dag.nix
      inputs.home-manager.nixosModules.home-manager
    ]
    # Account profiles (identity, groups, keys, password) from one structured data file.
    ++ lib.optional (builtins.pathExists ../../data/users.data.nix) ../../data/users.data.nix;

    # Which profiles this host takes from data/users.data.nix. The whole row (uid, groups, keys,
    # password file) arrives from the data file; the host no longer repeats it.
    kdn.userProfiles = [
      "bn"
      "root"
    ];

    kdn.hostName = "pryll";

    # Accepted usability defaults (run book owner item 4): Polish locale, `pl` keyboard, Warsaw
    # time. Set through the `locale` aspect options (the aspect is in the include list), so all
    # three classes (NixOS `i18n.*`/`time.timeZone`, the Home Manager session variables, and
    # user-dirs) follow one declaration. `pl_PL.UTF-8` is a 24-hour locale, so the Plasma clock
    # reads 24h once it follows the system locale; there is no separate clock option on this aspect.
    kdn.locale.primary = "pl_PL.UTF-8";
    # A plain assignment to a `listOf` option REPLACES the aspect `default` (it only concatenates
    # with another non-default definition), so restate the base locales here and add the Polish one.
    # `supportedLocales` must contain `primary` (`pl_PL.UTF-8/UTF-8`), and `C.UTF-8` /
    # `en_US.UTF-8` are kept so tools that expect a fallback locale do not break.
    kdn.locale.extra = [
      "C.UTF-8/UTF-8"
      "en_US.UTF-8/UTF-8"
      "en_GB.UTF-8/UTF-8"
      "pl_PL.UTF-8/UTF-8"
    ];
    kdn.locale.time = "pl_PL.UTF-8";
    kdn.locale.xkbLayout = "pl";
    kdn.locale.timezone = "Europe/Warsaw";

    # The CA host certificate, modelled on `hosts/brys/ssh-ca.nix`, so the already-included
    # `ssh-ca` aspect issues it: sshd serves the CA-signed host certificate and clients that trust
    # the `kdn` CA verify pryll by CA instead of by a pinned TOFU key.
    #
    # The leaf is declared only once the signing artifacts exist. The `certificates` aspect hard-
    # requires the committed `<directory>/<keyFile>.sops` (the SOPS-encrypted host key) and
    # `<directory>/<certFile>` (the CA-signed public certificate) at eval time, because it copies
    # them into the system closure. Producing them needs the fleet CA private key and the SOPS
    # recipients, so it is an OWNER HAND-OFF (run book phase 2c / owner item 5):
    #
    #   kdn-certs ssh host pryll
    #
    # generates the ed25519 host key, SOPS-encrypts it to `hosts-den/pryll/certs/
    # ssh_host_ed25519.key.sops`, signs `ssh_host_ed25519-cert.pub` with the `kdn` CA, and writes
    # both. Until then the `pathExists` guard keeps this change self-contained and the `ssh-ca`
    # aspect inert (a no-op, exactly as before the leaf), so pryll keeps its plain host key. The
    # moment the two files land the leaf activates and sshd presents the CA host certificate.
    #
    # `principals` names every form a client may connect with. pryll lives on the etra LAN
    # (`hosts/etra`: `hosts.lan.pryll`), so the short name plus `pryll.lan.etra.net.int.kdn.im`.
    # Add more (`pryll.lan.drek.net.int.kdn.im`, a netbird name) only when pryll actually joins
    # those networks. `kdn-certs` also signs the trailing-dot form of each FQDN at signing time.
    kdn.certificates.repoRoot = ../..;
    kdn.certificates.certs = lib.optionalAttrs (builtins.pathExists ./certs/ssh_host_ed25519-cert.pub) {
      ssh-host-pryll = {
        ca = "kdn";
        type = "ssh-host";
        commonName = "pryll";
        principals = [
          "pryll"
          "pryll.lan.etra.net.int.kdn.im"
        ];
        directory = "hosts-den/pryll/certs";
        certFile = "ssh_host_ed25519-cert.pub";
        keyFile = "ssh_host_ed25519.key";
        keySource = "managed";
      };
    };

    # Let the initrd emergency shell accept root (same hash). A failed LUKS prompt then drops
    # to a usable shell instead of locking the machine out entirely.
    kdn.profile-baseline.initrd.emergencyAccess = "$y$j9T$AhbnpYZawNWNGfuq1h9/p0$jmitwtZwTr72nBgvg2TEmrGmhRR30sQ.hQ7NZk1NqJD";
    networking.hostName = "pryll";
    networking.hostId = "25880d1d";
    system.stateVersion = "26.05";

    # Unattended updates (run book owner item): pull and switch on a weekly timer.
    #
    # CAVEAT — LUKS unlock path. This host's root is a detached-header LUKS volume on the
    # internal SSD. It unlocks only with a FIDO2 tap (YubiKey) or the keyslot-1 pass keyfile:
    # the machine's TPM is 1.2 and systemd-cryptenroll cannot enrol it, so there is NO
    # unattended unlock. A reboot drops the machine to the initrd LUKS prompt and it stays
    # offline until a person is physically present. Therefore `allowReboot` is left FALSE: the
    # timer does the safe part (fetch + switch, no reboot) and the new generation activates on
    # the next manual, attended restart. Flip `allowReboot` true only while someone is at the
    # machine; `rebootWindow` then bounds that reboot to the early-morning hour.
    system.autoUpgrade = {
      enable = true;
      dates = "sun *-*-* 04:30";
      randomizedDelaySec = "45min";
      operation = "switch";
      allowReboot = false;
      rebootWindow = {
        lower = "04:00";
        upper = "05:00";
      };
    };
    home-manager.useGlobalPkgs = true;
    home-manager.sharedModules = [ { home.stateVersion = "26.05"; } ];

    security.sudo.wheelNeedsPassword = false;

    # --- Backup skeleton (OWNER HAND-OFF) ---------------------------------
    # Restic backup of the persisted home state to a local USB disk. Left DISABLED on
    # purpose: activating it needs the owner to (1) mount the USB target and set a real
    # `repository` path, (2) create a restic password secret and point `passwordFile` at
    # it, and (3) confirm the persist mount (assumed `/persist` via the `disks-persist`
    # aspect) matches this host. With `enable = false` this is an inert, eval-clean
    # placeholder; nothing is scheduled and no missing-secret assertion fires.
    services.restic.backups.pryll-usb = {
      enable = false;
      repository = "/mnt/usb-backup/pryll";
      passwordFile = "/run/secrets/restic-pryll-password";
      paths = [ "/persist/home/bn" ];
      timerConfig = { OnCalendar = "daily"; };
    };

    # profile-baseline sets users.mutableUsers = false, and the root profile (selected below) hands
    # its hash to profile-baseline's `users.users.root.hashedPasswordFile`, so the nixpkgs "locked
    # out" assert is satisfied and mutableUsers stays false.

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
    environment.systemPackages = with hostPkgs; [
      rustdesk
      # Desktop apps wanted on the mother's workstation (run book owner item: document viewing,
      # image viewing, file manager, media player). `desktop-kde` only brings Plasma + the QQc2
      # breeze styles, so these are added here explicitly. okular/gwenview/dolphin are KDE apps,
      # vlc is a top-level package.
      kdePackages.okular
      kdePackages.gwenview
      kdePackages.dolphin
      vlc
    ];
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

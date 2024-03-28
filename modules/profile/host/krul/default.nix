{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.krul;
  hostname = config.networking.hostName;
in
{
  options.kdn.profile.host.krul = {
    enable = lib.mkEnableOption "enable krul host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home-manager.users.kdn.programs.firefox.profiles.kdn.path = "owvm95ih.kdn";
      home-manager.users.kdn.home.file.".mozilla/firefox/profiles.ini".force = true;

      kdn.profile.machine.workstation.enable = true;
      kdn.hardware.gpu.amd.enable = true;
      kdn.hardware.cpu.amd.enable = true;

      kdn.programs.photoprism.enable = false;

      services.nix-serve = {
        enable = false;
        secretKeyFile = "/var/nix-keys/krul.kdn.im/cache-priv-key.pem";
      };

      kdn.profile.machine.gaming.enable = true;

      boot.initrd.availableKernelModules = [
        "r8169" # Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller [10ec:8125] (rev 05)
        "igb" # Intel Corporation I211 Gigabit Network Connection [8086:1539] (rev 03)
      ];

      networking.interfaces.enp5s0.wakeOnLan.enable = true;
      networking.interfaces.enp6s0.wakeOnLan.enable = true;

      zramSwap.enable = lib.mkDefault true;
      zramSwap.memoryPercent = 50;
      zramSwap.priority = 100;

      kdn.hardware.edid.enable = true;
      hardware.display.outputs."DP-1".edid = "PG278Q_120.bin";
      hardware.display.outputs."DP-1".mode = "e";

      # 12G was not enough for large rebuild
      boot.tmp.tmpfsSize = "16G";
    }
    {
      home-manager.sharedModules = [{
        wayland.windowManager.sway.config =
          let
            # name is derived from forced edid profile, could be DP-1
            asus = "The Linux Foundation PG278Q_60 Linux #0";
            dell = "Dell Inc. DELL U2711 G606T29F0EWL";
          in
          {
            output."${asus}".pos = "0 0";
            output."${dell}".pos = "2560 0";
            workspaceOutputAssign = [
              { workspace = "1"; output = dell; }
              { workspace = "2"; output = asus; }
              { workspace = "3"; output = asus; }
              { workspace = "4"; output = dell; }
            ];
          };
      }];
    }
    (
      # TODO: remove it after reconfiguring zpool
      {
        disko.enableConfig = true;
        kdn.filesystems.disko.luks-zfs.enable = lib.mkForce false;
        boot.zfs.forceImportRoot = false;
        boot.zfs.requestEncryptionCredentials = false;
        boot.initrd.luks.forceLuksSupportInInitrd = true;
        boot.kernelParams =
          let
            disko = config.disko.devices;
            crypted = disko.disk.crypted-root;
            boot = disko.disk.boot;

            getArg = name: lib.trivial.pipe crypted.content.extraFormatArgs [
              (builtins.filter (lib.strings.hasPrefix "--${name}="))
              builtins.head
              (lib.strings.removePrefix "--${name}=")
            ];

            luksOpenName = crypted.content.name;
            rootUUID = getArg "uuid";
            headerPath = getArg "header";
            luksDevice = crypted.device;
          in
          [
            # https://www.freedesktop.org/software/systemd/man/systemd-cryptsetup-generator.html#
            "rd.luks.name=${rootUUID}=${luksOpenName}"
            "rd.luks.options=${rootUUID}=header=${headerPath}"
            "rd.luks.data=${rootUUID}=${luksDevice}"

            "video=DP-1:e" # edid fix see https://gitlab.freedesktop.org/drm/amd/-/issues/615#note_1987392
          ];
        # legacy mountpoints
        fileSystems =
          let
            mkZFSMountBase =
              { path
              , at ? path
              , poolPrefix ? ""
              }: {
                "${at}" = {
                  device = "${hostname}-main/${hostname}${poolPrefix}${path}";
                  fsType = "zfs";
                };
              };
            mkZFSMount = path: opts: mkZFSMountBase ({ inherit path; } // opts);
            mkContainerMount = path: opts: mkZFSMountBase ({ inherit path; poolPrefix = "/containers"; } // opts);
            mkNixOSMount = path: opts: mkZFSMountBase ({ inherit path; poolPrefix = "/nixos"; } // opts);
          in
          lib.mkMerge [
            (mkNixOSMount "/root" { at = "/"; })
            (mkNixOSMount "/etc" { })
            (mkNixOSMount "/nix" { })
            (mkNixOSMount "/var" { })
            (mkNixOSMount "/var/lib/libvirt" { })
            (mkNixOSMount "/var/lib/rook" { })
            (mkNixOSMount (config.microvm.stateDir or "/var/lib/microvms") { })
            (mkNixOSMount "/var/log" { })
            (mkNixOSMount "/var/log/journal" { })
            (mkNixOSMount "/var/spool" { })
            #(mkContainerMount "/containerd" { at = "/var/lib/containerd"; })
            (mkZFSMount "/home" { })
            (mkZFSMount "/home/kdn" { })
            (mkZFSMount "/home/kdn/.cache" { })
            (mkZFSMount "/home/kdn/.local" { })
            (mkZFSMount "/home/kdn/.local/share" { })
            #(mkZFSMount "/home/kdn/.local/share/containers" { })
            (mkZFSMount "/home/kdn/Downloads" { })
            (mkZFSMount "/home/kdn/Nextcloud" { })
            {
              "/boot".neededForBoot = true;
              "/var/log/journal".neededForBoot = true;
            }
          ];

      }
    )
    {
      kdn.filesystems.disko.luks-zfs.enable = true;
    }
    (import ./disko.nix { inherit lib; hostname = config.networking.hostName; })
  ]);
}

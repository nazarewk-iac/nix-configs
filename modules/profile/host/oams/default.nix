{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.profile.host.oams;

  debugBoot = true;

  trim = strip: txt: lib.pipe txt [
    (lib.strings.removePrefix strip)
    (lib.strings.removeSuffix strip)
  ];

  getValue = name: lib.pipe mountScriptLines [
    (lib.filter (lib.hasPrefix "${name}="))
    builtins.head
    (lib.strings.splitString "=")
    lib.lists.last
    (trim ''"'')
  ];

  mountScriptLines = lib.pipe (builtins.readFile ./mount.sh) [
    (lib.strings.splitString "\n")
  ];

  zfsPrefix = getValue "zfs_prefix";
  luksDevice = getValue "luks_device";
  rootUUID = getValue "root_uuid";
  headerFilename = getValue "header_name";

  zpool = lib.pipe zfsPrefix [
    (lib.strings.splitString "/")
    builtins.head
  ];

  bootPath = lib.pipe mountScriptLines [
    (lib.filter (lib.hasInfix "/dev/disk/by-uuid"))
    builtins.head
    (lib.strings.splitString " ")
    (lib.filter (lib.hasInfix "/dev/disk/by-uuid"))
    builtins.head
    (trim ''"'')
  ];

  bootUUID = lib.pipe bootPath [
    (lib.strings.splitString "/")
    lib.lists.last
  ];

  zfsMountPaths = lib.pipe mountScriptLines [
    (lib.filter (lib.hasPrefix "setupZFS "))
    (builtins.map (entry: lib.pipe entry [
      # for whatever reason (lib.strings.splitString " ") was not working, using builtins.split then filter,
      # becaus split is regex-based and returns match lists in between
      (builtins.split " +")
      (builtins.filter builtins.isString)
      (l: builtins.elemAt l 1)
      (trim ''"'')
    ]))
  ];
in
{
  options.kdn.profile.host.oams = {
    enable = lib.mkEnableOption "enable oams host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.machine.workstation.enable = true;
      kdn.hardware.gpu.amd.enable = true;

      boot.zfs.forceImportRoot = false;
      boot.zfs.requestEncryptionCredentials = false;

      # enables systemd-cryptsetup-generator
      # see https://github.com/nazarewk/nixpkgs/blob/04f574a1c0fde90b51bf68198e2297ca4e7cccf4/nixos/modules/system/boot/luksroot.nix#L997-L1012
      boot.initrd.luks.forceLuksSupportInInitrd = true;
      boot.initrd.systemd = {
        enable = true;
      };

      boot.kernelParams = [
        # https://www.freedesktop.org/software/systemd/man/systemd-cryptsetup-generator.html#
        "rd.luks.name=${rootUUID}=${zpool}"
        "rd.luks.options=${rootUUID}=header=/${headerFilename}:UUID=${bootUUID}"
        "rd.luks.data=${rootUUID}=${luksDevice}"
        # see https://www.thegeekdiary.com/how-to-debug-systemd-boot-process-in-centos-rhel-7-and-8-2/
        "plymouth.enable=0"
        #"systemd.confirm_spawn=true"
        "systemd.debug-shell=1"
        "systemd.log_level=debug"
        "systemd.unit=multi-user.target"
      ];

      fileSystems = lib.pipe [
        {
          "/boot" = {
            device = bootPath;
            fsType = "vfat";
          };
        }
        (lib.pipe zfsMountPaths [
          (builtins.map (path: {
            "${path}" = {
              device = "${zfsPrefix}/${path}";
              fsType = "zfs";
            };
          }))
        ])
      ] [
        lib.lists.flatten
        lib.mkMerge
      ];
    }
    (lib.mkIf debugBoot {
      boot.initrd.systemd.emergencyAccess = true;
      boot.kernelParams = [
        # see https://www.thegeekdiary.com/how-to-debug-systemd-boot-process-in-centos-rhel-7-and-8-2/
        "plymouth.enable=0"
        #"systemd.confirm_spawn=true"  # this seems to ask and times out before executing anything during boot
        "systemd.debug-shell=1"
        "systemd.log_level=debug"
        "systemd.unit=multi-user.target"
      ];
    })
  ]);
}

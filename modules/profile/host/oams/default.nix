{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.profile.host.oams;

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

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.workstation.enable = true;
    kdn.hardware.gpu.amd.enable = true;

    boot.zfs.forceImportRoot = false;
    boot.zfs.requestEncryptionCredentials = [ ];

    boot.kernelParams = [
      "rd.luks.name=${rootUUID}=${zpool}"
      "rd.luks.options=${rootUUID}=header=/${headerFilename}:UUID=${bootUUID}"
      "rd.luks.data=${rootUUID}=${luksDevice}"
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
  };
}

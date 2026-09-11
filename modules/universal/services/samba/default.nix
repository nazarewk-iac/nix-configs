{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.services.samba;
in
{
  options.kdn.services.samba = {
    enable = lib.mkEnableOption "SMB shares setup";
    defaults.hostsAllow = lib.mkOption {
      type = with lib.types; listOf str;
      # The fallback names loopback only. `data/universal-safe/services-samba.nix` adds
      # the owner's LAN, and a consumer with no data folder states its own network here.
      default = [
        "127.0.0.0/8"
        "localhost"
        "::1"
      ];
      example = [
        "10.0.0.0/8"
        "127.0.0.0/8"
        "localhost"
        "::1"
      ];
    };
    defaults.hostsDeny = lib.mkOption {
      type = with lib.types; listOf str;
      default = [
        "0.0.0.0/0"
        "::/0"
      ];
    };
    defaults.workgroup = lib.mkOption {
      type = lib.types.str;
      default = "KDN";
      example = "WORKGROUP";
      description = ''
        SMB workgroup name. The default is this repository's own name, so a consumer that wants
        the Windows default states `WORKGROUP` itself.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.services.samba = lib.mkDefault cfg; } ];
      })
      (kdnConfig.util.ifTypes [ "nixos" ] {
        services.samba.enable = true;
        services.samba.openFirewall = true;
        services.samba.usershares.enable = true;
        services.samba.settings.global = {
          "workgroup" = cfg.defaults.workgroup;
          "server string" = "${config.kdn.hostName}-SMB";
          "netbios name" = config.kdn.hostName;
          "security" = "user";
          #"use sendfile" = "yes";
          #"max protocol" = "smb2";
          # note: localhost is the ipv6 localhost ::1
          "hosts allow" = builtins.concatStringsSep " " cfg.defaults.hostsAllow;
          "hosts deny" = builtins.concatStringsSep " " cfg.defaults.hostsDeny;
          "guest account" = "nobody";
          "map to guest" = "bad user";

          "create mask" = "0640";
          "directory mask" = "0751";
          "browseable" = "no";
          "writeable" = "no";
          "read only" = "yes";
        };
      })
      {
        kdn.disks.persist."sys/data".directories = [
          "/var/lib/samba"
        ];
        kdn.disks.persist."usr/data".directories = [
          (config.services.samba.settings.global."usershare path" or "/var/lib/samba/usershares")
        ];
      }
    ]
  );
}

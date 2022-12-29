{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.headless;
in
{
  options.kdn.headless = {
    enableGUI = lib.mkEnableOption "tells the rest of configs to enable/disable GUI applications";
  };

  config = lib.mkMerge [
    {
      boot.kernelParams = [
        "plymouth.enable=0" # disable boot splash screen
      ];
      home-manager.sharedModules = [
        ({ lib, ... }: {
          options.kdn.headless = {
            enableGUI = lib.mkOption {
              type = lib.types.bool;
              default = cfg.enableGUI;
            };
          };
        })
      ];
    }
    (lib.mkIf config.boot.initrd.systemd.enable {
      specialisation.systemd-boot-debug = {
        inheritParentConfig = true;
        configuration = lib.mkMerge [
          {
            system.nixos.tags = [ "boot-debug" ];
            boot.initrd.systemd.emergencyAccess = true;
            boot.kernelParams = [
              # see https://www.thegeekdiary.com/how-to-debug-systemd-boot-process-in-centos-rhel-7-and-8-2/
              #"systemd.confirm_spawn=true"  # this seems to ask and times out before executing anything during boot
              "systemd.debug-shell=1"
              "systemd.log_level=debug"
              "systemd.unit=multi-user.target"
            ];
          }
        ];
      };
    })
  ];
}

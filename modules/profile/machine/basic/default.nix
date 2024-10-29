{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.profile.machine.basic;
in
{
  options.kdn.profile.machine.basic = {
    enable = lib.mkEnableOption "basic machine profile for interactive use";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.machine.baseline.enable = true;
      kdn.programs.gnupg.enable = true;

      networking.networkmanager.wifi.powersave = true;

      boot.loader.systemd-boot.memtest86.enable = true;

      # HARDWARE
      hardware.usb-modeswitch.enable = true;
      environment.systemPackages = with pkgs; [ usb-modeswitch ];
      kdn.hardware.bluetooth.enable = true;
    }
    (
      let
        kdn-man-gen-caches = pkgs.writeShellApplication {
          name = "kdn-man-gen-caches";
          runtimeInputs = with pkgs; [
            coreutils
          ];
          text = ''
            if [[ $EUID -ne 0 ]]; then
              echo "restarting as root..." >&2
              exec sudo "$BASH" "$0" "$@"
            fi

            mkdir -p /var/cache/man/nixos
            ${lib.getExe' config.documentation.man.man-db.package "mandb"} "$@"
          '';
        };
      in
      {
        documentation.man.man-db.enable = true;
        documentation.man.generateCaches = false;
        environment.systemPackages = [ kdn-man-gen-caches ];
        environment.persistence."sys/cache".directories = [
          "/var/cache/man/nixos"
        ];
        systemd.services.kdn-man-gen-caches = {
          wantedBy = [ "multi-user.target" ];
          description = "generates manpage caches during runtime instead of during build";
          serviceConfig.Type = "oneshot";
          serviceConfig.RemainAfterExit = true;
          serviceConfig.ExecStart = lib.strings.escapeShellArgs [
            (lib.getExe kdn-man-gen-caches)
          ];
        };
        system.activationScripts.kdn-man-gen-caches.deps =
          let
            ifExists = name: lib.optional (config.system.activationScripts ? name) name;
          in
          [ "etc" ]
          ++ ifExists "impermanenceCreatePersistentStorageDirs"
          ++ ifExists "impermanencePersistFiles"
        ;
        system.activationScripts.kdn-man-gen-caches.text = ''
          ${lib.getExe' pkgs.systemd "systemctl"} start --no-block kdn-man-gen-caches.service
        '';
      }
    )
    {
      environment.systemPackages = with pkgs; [
        lsix # image thumbnails in terminal
      ];
    }
    (lib.mkIf config.boot.initrd.systemd.enable {
      specialisation.debug = {
        inheritParentConfig = true;
        configuration = {
          system.nixos.tags = [ "debug" ];
          boot.kernelParams = [
            # see https://www.thegeekdiary.com/how-to-debug-systemd-boot-process-in-centos-rhel-7-and-8-2/
            #"systemd.confirm_spawn=true"  # this seems to ask and times out before executing anything during boot
            "systemd.debug-shell=1"
            "systemd.log_level=debug"
          ];
        };
      };
      specialisation.rescue = {
        inheritParentConfig = true;
        configuration = {
          system.nixos.tags = [ "rescue" ];
          systemd.defaultUnit = lib.mkForce "rescue.target";
          boot.kernelParams = [
            # see https://www.thegeekdiary.com/how-to-debug-systemd-boot-process-in-centos-rhel-7-and-8-2/
            #"systemd.confirm_spawn=true"  # this seems to ask and times out before executing anything during boot
            "systemd.debug-shell=1"
            "systemd.log_level=debug"
          ];
        };
      };
    })
  ]);
}

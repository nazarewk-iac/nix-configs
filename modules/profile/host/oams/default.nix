{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.profile.host.oams;
in
{
  options.kdn.profile.host.oams = {
    enable = lib.mkEnableOption "enable oams host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home-manager.users.kdn.programs.firefox.profiles.kdn.path = "v6uzqa6m.default";
      home-manager.users.kdn.home.file.".mozilla/firefox/profiles.ini".force = true;

      kdn.profile.machine.workstation.enable = true;
      kdn.hardware.gpu.amd.enable = true;
      kdn.hardware.cpu.amd.enable = true;

      kdn.profile.machine.gaming.enable = true;
      kdn.hardware.gpu.vfio.enable = lib.mkForce false;
      kdn.hardware.gpu.vfio.gpuIDs = [
        "1002:73df"
        "1002:ab28"
      ];

      systemd.tmpfiles.rules = [
        "f /dev/shm/looking-glass 0660 kdn qemu-libvirtd -"
      ];

      kdn.filesystems.disko.luks-zfs.enable = true;

      boot.kernelModules = [ "kvm-amd" ];

      services.asusd.enable = true;
      kdn.hardware.gpu.multiGPU.enable = true;
      services.asusd.enableUserService = false; # just strobes the LEDs, better turn it off
      environment.systemPackages = with pkgs; [
        asusctl
      ];
    }
    (import ./disko.nix { inherit lib; hostname = config.networking.hostName; })
    (
      let
        internal = "Chimei Innolux Corporation 0x1540 Unknown";
        m32uc = "GIGA-BYTE TECHNOLOGY CO., LTD. M32UC 22090B013112";
      in
      {
        home-manager.sharedModules = [{
          wayland.windowManager.sway.config = {
            output."${internal}" = {
              pos = "3840 720";
              mode = "2560x1440@60Hz";
            };
            output."${m32uc}" = {
              pos = "0 0";
              mode = "3840x2160@144Hz";
            };
            workspaceOutputAssign = [
              { workspace = "1"; output = m32uc; }
              { workspace = "2"; output = internal; }
              { workspace = "3"; output = internal; }
              { workspace = "4"; output = m32uc; }
            ];
          };
        }];
      }
    )
  ]);
}

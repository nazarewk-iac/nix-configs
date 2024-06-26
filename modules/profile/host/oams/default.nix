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

      # 12G was not enough for large rebuild
      boot.tmp.tmpfsSize = "32G";
    }
    {
      services.asusd.enable = true;
      kdn.hardware.gpu.multiGPU.enable = true;
      programs.ryzen-monitor-ng.enable = true;
      hardware.cpu.amd.ryzen-smu.enable = true;
      programs.rog-control-center.enable = true;
      programs.rog-control-center.autoStart = true;
      services.asusd.enableUserService = true;
      environment.systemPackages = with pkgs; [
        ryzenadj
      ];
      home-manager.sharedModules = [
        (args:
          let
            bin = lib.getExe' config.services.asusd.package;
            exec = cmd: args: "exec '${bin cmd} ${args}'";
            key = {
              # Top row of keys (between function keys and screen)
              top.vol-down = "XF86AudioLowerVolume"; # Top row volume down
              top.vol-up = "XF86AudioRaiseVolume"; # Top row volume down
              top.mic = "XF86AudioMicMute"; # Top row Microphone button
              top.fan = "XF86Launch4"; # Top row Fan button
              top.rog = "XF86Launch1"; # Top row RoG Eye logo button

              # "FN" key activated functions
              fn.f1 = "XF86AudioMute";
              fn.f2 = "XF86KbdBrightnessDown";
              fn.f3 = "XF86KbdBrightnessUp";
              fn.f4 = "XF86Launch3"; # "AURA" button
              fn.f5 = "XF86Launch4"; # Fan button
              fn.f6 = "Shift+Mod4"; # Snip button
              fn.f7 = "XF86MonBrightnessDown";
              fn.f8 = "XF86MonBrightnessUp";
              fn.f9 = "Mod4+P"; # Display switch button
              fn.f10 = "XF86TouchpadToggle"; # crossed touchpad button
              fn.f11 = "XF86Sleep"; # zZ button, works OOTB on Sway on NixOS
              fn.f12 = "XF86RFKill"; # airplane button, works OOTP on Sway on Nixos
              fn.delete = "Insert"; # Delete / Insert button
              fn.rctrl = "Menu"; # Right CTRL with menu icon
              fn.arrow-left = "Home";
              fn.arrow-up = "Prior";
              fn.arrow-down = "Next";
              fn.arrow-right = "End";

              # right-hand side button row
              right.play = "XF86AudioPlay";
              right.stop = "XF86AudioStop";
              right.prev = "XF86AudioPrev";
              right.next = "XF86AudioNext";
              right.PrtSc = "Sys_Req"; # PrtSc aka Print Screen button
            };
          in
          {
            wayland.windowManager.sway.config.keybindings = {
              "${key.top.fan}" = exec "asusctl" "profile -n";
              "${key.top.rog}" = exec "rog-control-center" "";
              "${key.fn.f2}" = exec "asusctl" "--prev-kbd-bright";
              "${key.fn.f3}" = exec "asusctl" "--next-kbd-bright";
            };
          })
      ];
    }
    (import ./disko.nix { inherit lib; hostname = config.networking.hostName; })
  ]);
}

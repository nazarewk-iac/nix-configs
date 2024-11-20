{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.kdn.profile.host.oams;
in {
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

      systemd.tmpfiles.rules = [
        "f /dev/shm/looking-glass 0660 kdn qemu-libvirtd -"
      ];

      kdn.filesystems.disko.luks-zfs.enable = true;

      boot.kernelModules = ["kvm-amd"];

      # 12G was not enough for large rebuild
      boot.tmp.tmpfsSize = "32G";
    }
    /*
      {
      kdn.hardware.edid.enable = true;
      hardware.display.outputs."DP-1" = {
        edid = "PG278Q_120.bin";
        mode = "e";
      };
    }
    */
    {
      services.asusd.enable = true;
      kdn.hardware.gpu.multiGPU.enable = true;
      programs.rog-control-center.enable = true;
      programs.rog-control-center.autoStart = true;
      services.asusd.enableUserService = true;
      home-manager.sharedModules = [
        (args: let
          bin = lib.getExe' config.services.asusd.package;
          exec = cmd: args: "exec '${bin cmd} ${args}'";
        in {
          wayland.windowManager.sway.config.keybindings = with config.kdn.desktop.sway.keys; {
            "${oams.top.fan}" = exec "asusctl" "profile -n";
            "${oams.top.rog}" = exec "rog-control-center" "";
            "${oams.fn.f2}" = exec "asusctl" "--prev-kbd-bright";
            "${oams.fn.f3}" = exec "asusctl" "--next-kbd-bright";
          };
        })
      ];

      kdn.desktop.sway.keys.oams = {
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
    }
    (import ./disko.nix {
      inherit lib;
      hostname = config.networking.hostName;
    })
    {
      networking.networkmanager.logLevel = "DEBUG";
    }
    {
      specialisation.gaming = {
        inheritParentConfig = true;
        configuration = {
          system.nixos.tags = ["gaming"];
          kdn.hardware.gpu.supergfxd.mode = lib.mkForce "Hybrid";
          kdn.profile.machine.gaming.enable = true;
          kdn.profile.machine.gaming.vulkan.deviceId = "1002:73df";
          kdn.profile.machine.gaming.vulkan.deviceName = "AMD Radeon RX 6800M";
        };
      };
    }
    {
      specialisation.vfio = {
        inheritParentConfig = true;
        configuration = {
          system.nixos.tags = ["vfio"];
          kdn.hardware.gpu.vfio.enable = true;
          kdn.hardware.gpu.vfio.gpuIDs = [
            "1002:73df"
            "1002:ab28"
          ];
        };
      };
    }
  ]);
}

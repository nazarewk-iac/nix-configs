{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}: {
  imports = [
    kdnConfig.self.nixosModules.default
  ];

  config = lib.mkMerge [
    {
      kdn.hostName = "oams";

      system.stateVersion = "23.11";
      home-manager.sharedModules = [{home.stateVersion = "23.11";}];
      networking.hostId = "ce0f2f33"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      home-manager.users.kdn.programs.firefox.profiles.kdn.path = "v6uzqa6m.default";
      home-manager.users.kdn.home.file.".mozilla/firefox/profiles.ini".force = true;

      kdn.profile.machine.workstation.enable = true;
      kdn.hw.gpu.amd.enable = true;
      kdn.hw.cpu.amd.enable = true;

      systemd.tmpfiles.rules = [
        "f /dev/shm/looking-glass 0660 kdn qemu-libvirtd -"
      ];

      kdn.fs.disko.luks-zfs.enable = true;

      boot.kernelModules = ["kvm-amd"];

      # 12G was not enough for large rebuild
      boot.tmp.tmpfsSize = "32G";
    }
    /*
      {
      kdn.hw.edid.enable = true;
      hardware.display.outputs."DP-1" = {
        edid = "PG278Q_120.bin";
        mode = "e";
      };
    }
    */
    {
      services.asusd.enable = true;
      kdn.hw.gpu.multiGPU.enable = true;
      programs.rog-control-center.enable = true;
      programs.rog-control-center.autoStart = true;
      services.asusd.enableUserService = true;
      home-manager.sharedModules = [
        (
          args: let
            kdn-asusctl = pkgs.writeShellApplication {
              name = "kdn-asusctl";
              runtimeInputs = with pkgs; [
                config.services.asusd.package
                libnotify
                coreutils
              ];
              text = ''
                asusctl() {
                  RUST_LOG="''${RUST_LOG:-"warn,tracing=warn,zbus=warn"}" command asusctl "$@"
                }
                cmd_rotate-cpu-profile() {
                  asusctl profile --next
                  notify-send "CPU profile" "Current CPU profile: $(asusctl profile --profile-get)"
                }

                cmd_rotate-keyboard-brightness() {
                  local to
                  case "''${1:-"next"}" in
                    prev)
                      to="prev"
                    ;;
                    next)
                      to="next"
                    ;;
                    *)
                      return 1
                    ;;
                  esac
                  asusctl "--$to-kbd-bright"
                  notify-send "Keyboard LED brightness" "changed to $to"
                }

                "cmd_''${1}" "''${@:2}"
              '';
            };
            run = lib.getExe kdn-asusctl;
          in {
            home.packages = [kdn-asusctl];
            wayland.windowManager.sway.config.keybindings = with config.kdn.desktop.sway.keys; {
              "${oams.top.fan}" = "exec '${run} rotate-cpu-profile'";
              "${oams.top.rog}" = "exec '${run} rog-control-center'";
              "${oams.fn.f2}" = "exec '${run} rotate-keyboard-brightness prev'";
              "${oams.fn.f3}" = "exec '${run} rotate-keyboard-brightness next'";
              "${shift}+${super}+P" = "output eDP-1 toggle";
            };
          }
        )
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
      hostname = config.kdn.hostName;
    })
    {
      networking.networkmanager.logLevel = "DEBUG";
    }
    {
      # keep all the mountpoints and software available
      kdn.profile.machine.gaming.enable = true;
      specialisation.gaming = {
        # reboot into dGPU accelerated specialisation
        inheritParentConfig = true;
        configuration = {
          system.nixos.tags = ["gaming"];
          kdn.hw.gpu.supergfxd.mode = lib.mkForce "Hybrid";
          kdn.profile.machine.gaming.vulkan.deviceId = "1002:73df";
          kdn.profile.machine.gaming.vulkan.deviceName = "AMD Radeon RX 6800M";
          home-manager.sharedModules = [
            {
              kdn.desktop.sway.kanshi.devices.oams.scale = lib.mkForce 1.0;
            }
          ];
        };
      };
    }
    {
      specialisation.vfio = {
        inheritParentConfig = true;
        configuration = {
          system.nixos.tags = ["vfio"];
          kdn.hw.gpu.vfio.enable = true;
          kdn.hw.gpu.vfio.gpuIDs = [
            "1002:73df"
            "1002:ab28"
          ];
        };
      };
    }
    {
      # need to allow for a Netbird assignment
      networking.firewall.trustedInterfaces = ["tun0"];
      systemd.network.wait-online.enable = false;
    }
    {
      # kdn.nix.remote-builder.localhost.publicHostKey = "??";
      kdn.nix.remote-builder.localhost.maxJobs = 6;
      kdn.nix.remote-builder.localhost.speedFactor = 16;
    }
    {
      kdn.fs.zfs.containers.fsname = "oams-main/containers/storage";
    }
  ];
}

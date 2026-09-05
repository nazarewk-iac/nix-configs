{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}: let
  slots = kdnConfig.self.mkSlots {
    inherit pkgs;
    # devenv CLI and shell hooks.
    kdn.devenv.enable = true;

    # Trust the KDN CA system-wide so the brys LLM leaf cert verifies. As a
    # development machine, oams also mounts the (encrypted, offliine) CA key blob
    # for manual reference; it does NOT host the LLM solution, so no leaf cert.
    kdn.ca.kdn.enable = true;
    kdn.ca.kdn.certFile = "${kdnConfig.self}/data/ca.pub";
    kdn.ca.kdn.keySopsFile = "${kdnConfig.self}/data/ca.key.sops";
  };
in {
  imports = [
    kdnConfig.self.nixosModules.default
    slots.config.nixos
  ];

  config = lib.mkMerge [
    {
      home-manager.sharedModules = [slots.config.home];
    }
    {
      kdn.hostName = "oams";

      system.stateVersion = "26.05";
      home-manager.sharedModules = [{home.stateVersion = "26.05";}];
      networking.hostId = "ce0f2f33"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      home-manager.users.kdn.programs.firefox.profiles.kdn.path = "v6uzqa6m.default";
      home-manager.users.kdn.home.file.".config/mozilla/firefox/profiles.ini".force = true;

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
      # nixpkgs `programs.rog-control-center.autoStart` calls
      # `makeAutostartItem { name = "rog-control-center"; }` with no `srcPrefix`.
      # asusctl 6.4.0 renamed the desktop file to
      # `org.opengamingcollective.rog-control-center.desktop`, so the module's
      # autostart derivation fails on the missing old-named file. Keep autoStart
      # off and add our own autostart item with the correct `srcPrefix`.
      programs.rog-control-center.autoStart = false;
      kdn.env.packages = [
        (pkgs.makeAutostartItem {
          name = "rog-control-center";
          package = config.services.asusd.package;
          srcPrefix = "org.opengamingcollective.";
        })
      ];
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
                  local to new
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
                  asusctl leds "$to"
                  new="$(asusctl leds get)"
                  notify-send "Keyboard LED brightness" "changed to $new"
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
      # Join the shared brys LAN VLANs from oams. NetworkManager VLAN profiles
      # REQUIRE a concrete parent device (an empty/unmatched parent is silently
      # dropped on reload), so these are bound to oams' ethernet NIC `enp4s0`,
      # mirroring the existing working `VLAN: pic` profile on this host.
      #
      # None of these AUTO-CONNECT: bring one up manually with
      #   nmcli connection up vlan-<pic|mgmt|drek>
      #
      # Addressing mirrors brys' per-VLAN scheme: DHCP is primary (brys runs
      # `dynamicIPClient` on each), and each also carries a static secondary
      # address as a guaranteed fallback so the VLAN has an IP even when no
      # DHCP server answers. oams picks a distinct host IP on the same subnet
      # as brys so the two never collide. If you plug the cable into a
      # different NIC, change `vlan.parent` to that device.
      networking.networkmanager.ensureProfiles.profiles = {
        vlan-pic = {
          connection = {
            id = "vlan-pic";
            type = "vlan";
            interface-name = "pic";
            autoconnect = "no";
            permissions = "user:kdn:;";
          };
          ethernet = {};
          vlan = {
            id = 1859;
            parent = "enp4s0";
          };
          ipv4 = {
            method = "auto"; # DHCP, fallback to static below
            address1 = "10.92.0.6/24"; # brys .5 / oams .6
            may-fail = "yes";
          };
          ipv6 = {
            method = "auto";
            addr-gen-mode = "stable-privacy";
          };
        };
        vlan-mgmt = {
          connection = {
            id = "vlan-mgmt";
            type = "vlan";
            interface-name = "mgmt";
            autoconnect = "no";
            permissions = "user:kdn:;";
          };
          ethernet = {};
          vlan = {
            id = 946;
            parent = "enp4s0";
          };
          ipv4 = {
            method = "auto"; # DHCP, fallback to static below
            address1 = "192.168.252.33/24"; # brys .32 / oams .33
            may-fail = "yes";
          };
          ipv6 = {
            method = "auto";
            addr-gen-mode = "stable-privacy";
          };
        };
        vlan-drek = {
          connection = {
            id = "vlan-drek";
            type = "vlan";
            interface-name = "drek";
            autoconnect = "no";
            permissions = "user:kdn:;";
          };
          ethernet = {};
          vlan = {
            id = 3547;
            parent = "enp4s0";
          };
          ipv4 = {
            method = "auto"; # DHCP, fallback to static below
            address1 = "192.168.41.32/24"; # brys .31 / oams .32
            may-fail = "yes";
          };
          ipv6 = {
            method = "auto";
            addr-gen-mode = "stable-privacy";
          };
        };
      };
    }
    {
      # keep all the mountpoints and software available
      kdn.profile.machine.gaming.enable = true;
      # kdn.profile.machine.gaming.vulkan.deviceId = "1002:73df";
      # kdn.profile.machine.gaming.vulkan.deviceName = "AMD Radeon RX 6800M";

      kdn.env.packages = [
        pkgs.kdn.kdn-gamingctl
      ];
      kdn.hw.gpu.supergfxd.mode = null;
    }
    (lib.mkIf false {
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
    })
    {
      # kdn.nix.remote-builder.localhost.publicHostKey = "??";
      kdn.nix.remote-builder.localhost.maxJobs = 6;
      kdn.nix.remote-builder.localhost.speedFactor = 16;
    }
    {
      kdn.fs.zfs.containers.fsname = "oams-main/containers/storage";
    }
    {
      kdn.services.samba.enable = true;
    }
    {
      security.sudo.wheelNeedsPassword = false;
    }
    {
      # Shared /run/configs/llms secrets (same mount as brys): HF token and
      # llama-server API keys. The leaf cert moved to hosts/brys/ (brys only).
      kdn.security.secrets.sops.files."llms" = {
        sopsFile = "${kdnConfig.self}/llms.nonsensitive.sops.yaml";
        basePath = "/run/configs/llms";
        sops.mode = "0444";
      };
    }
    {
      services.angrr.enable = false;
    }
  ];
}

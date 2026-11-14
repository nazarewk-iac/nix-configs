{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}:
let
  # Local LLM serving (task docs/tasks/2026-11/oams-llm-host/). This projects
  # data/llm.nix's `servers.oams` into `kdn.llm.local` and adds the RX 6800M
  # Vulkan runtime config. Leaner than brys: no TLS/leaf-key, no on-host
  # Prometheus (both centralised on the LiteLLM gateway host).
  llm = import ./llm.nix {
    inherit lib pkgs kdnConfig;
    profile = "desktop";
  };

  slots = kdnConfig.self.mkSlots {
    inherit pkgs;
    # kdn's own host connectivity graph (moss/etra/drek/oams/brys/anji).
    imports = builtins.filter builtins.pathExists [
      "${kdnConfig.self}/data/slots/slots-ssh-access.nix"
    ];

    # devenv CLI and shell hooks.
    kdn.devenv.enable = true;

    # Topology-aware remote SSH access (kdn-* dispatcher); graph comes from the import above.
    kdn.ssh-access.enable = true;

    # Trust the KDN CA system-wide so the brys LLM leaf cert verifies. As a
    # development machine, oams also mounts the (encrypted, offliine) CA key blob
    # for manual reference; it does NOT host the LLM solution, so no leaf cert.
    kdn.ca.kdn.enable = true;
    kdn.ca.kdn.certFile = "${kdnConfig.self}/data/ca/ca.pub";
    kdn.ca.kdn.keySopsFile = "${kdnConfig.self}/data/ca/ca.key.sops";
  };
in
{
  imports = [
    ({ kdn.pkgs.pin = true; })
    kdnConfig.self.nixosModules.default
    slots.config.nixos
    "${kdnConfig.self}/data/ca/ca-dag.nix"
    # LLM serving: secrets file, stats collector, model/session dirs.
    llm.nixos
    # The `kdn.llm.local` slot assignments from data/llm.nix.
    llm.slot
    {
      imports = kdnConfig.self.denLib.imports {
        class = "nixos";
        aspects = [
          "build-farm"
          "ca-dag"
          "certificates"
          "llm"
          "ssh-ca"
          "web-exposure"
        ];
      };
    }
  ];

  config = lib.mkMerge [
    {
      # Per-service HTTPS exposure: llama-swap on its own subdomain (served from
      # the loopback llama-swap, so its absolute /ui and /v1 paths work unchanged).
      kdn.web.exposure = {
        domain = "oams.priv.nb.net.int.kdn.im";
        certName = "zellij-web";
        title = "oams";
        listenAddresses = [ "100.79.80.79" ];
        networkServices = [ "netbird-priv.service" ];
        services = {
          llama-swap = {
            subdomain = "llama-swap.oams.priv.nb.net.int.kdn.im";
            upstream = "127.0.0.1:39700";
          };
        };
      };
    }
    # The RX 6800M Vulkan runtime config (hardware.graphics, mesa, and the
    # MESA_VK_DEVICE_SELECT pin to 1002:73df), owned by ./llm.nix.
    llm.gpu
    {
      # Build-farm client: one `buildMachines` entry per system set, each at that set's proxy
      # port. See data/build-farm.nix.
      kdn.build-farm = (import ../../data/build-farm.nix).oams;

      # The universal `remote-builders` profile still supplies the builder SSH key and account, so
      # it stays enabled, but its static per-suffix builder list is now dead weight: `nix.buildMachines`
      # is a list option and concatenates every definition, so that list would sit next to the proxy
      # entries and double-count the same hosts. Empty it; the build-farm aspects own the fleet.
      kdn.profile.remote-builders.buildMachines = lib.mkForce [ ];

      # oams signs the store paths it builds locally, so a builder that keeps `require-sigs` on can
      # accept them as build inputs (otherwise: "lacks a signature by a trusted key"). The secret
      # half is host-specific: it lives in hosts/oams/secrets.sops.yaml, decryptable only by this
      # host (boot) and the oams + brys YubiKeys — not the fleet-wide default file. The public half
      # is in data/nix-signing-keys.nix, trusted by every host.
      kdn.security.secrets.sops.files."signing" = {
        keyPrefix = "nix/signing";
        sopsFile = "${kdnConfig.self}/hosts/oams/secrets.sops.yaml";
        basePath = "/run/configs";
        namePrefix = "signing";
        sops.mode = "0400";
      };
      nix.settings.secret-key-files = [ "/run/configs/nix/signing/oams-1" ];
    }
    {
      home-manager.sharedModules = [ slots.config.home ];
    }
    {
      # SSH CA client trust for the kdn user. The `50-kdn-ssh-ca.config` drop-in presents
      # `~/.ssh/id_ed25519-cert.pub`, the user certificate written by `kdn-certs ssh login <host>`,
      # and the managed `known_hosts` fragment trusts every host certificate the KDN CA signs.
      # Inclusion is the switch: the aspect carries no `enable` option.
      home-manager.sharedModules =
        (kdnConfig.self.denLib.imports {
          class = "homeManager";
          aspects = [
            "ssh-ca"
            "pi-client"
          ];
        })
        ++ [
          # The home-manager copy of the option trees resolves the CA path the same way, so it
          # needs the CA node and the repository root too.
          "${kdnConfig.self}/data/ca/ca-dag.nix"
          {
            kdn.certificates.repoRoot = kdnConfig.self;
            # The CA user certificate is offered to these hosts only. It must be set in the
            # home-manager evaluation, because that is where the drop-in is generated; a value in
            # the host module never reaches it. One definition, shared with the `kdn-ssh-access`
            # agent patterns in data/net/ssh-hosts.nix.
            kdn.ssh-ca.certificatePatterns = (import ../../data/net/ssh-hosts.nix).patterns;
          }
        ];
    }
    {
      kdn.hostName = "oams";

      system.stateVersion = "26.05";
      home-manager.sharedModules = [ { home.stateVersion = "26.05"; } ];
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

      boot.kernelModules = [ "kvm-amd" ];

      # Cap the ZFS ARC at 8 GiB, the same value brys uses. Without it the ARC grows to about
      # half of RAM (measured ~25 GiB of 62 GiB here) and competes with a Pi harness that spawns
      # one process per subagent. 8 GiB still caches ordinary file I/O. 8589934592 = 8 GiB.
      boot.kernelParams = [ "zfs.zfs_arc_max=8589934592" ];

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
      # G513QY (product id 0x1866) edge lightbar pulses red on suspend whenever
      # the keyboard zone has `sleep: true`. asusctl 6.4.0 changed the default
      # for pre-2021 devices from one merged KeyboardAndLightbar state (all
      # false) to per-zone states defaulting to all true, so the regenerated
      # aura_1866.ron re-enabled the suspend animation. Pin the file so the
      # keyboard stays lit while awake but both zones stay dark on sleep.
      services.asusd.auraConfigs."1866".source = ./aura_1866.ron;
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
          args:
          let
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
          in
          {
            home.packages = [ kdn-asusctl ];
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
      # `dynamicIPClient` on each). `pic` and `mgmt` also carry a static
      # secondary address as a guaranteed fallback, so the VLAN has an IP even
      # when no DHCP server answers. oams picks a distinct host IP on the same
      # subnet as brys so the two never collide. A static fallback is only safe
      # outside the subnet's DHCP pool — `drek` therefore runs DHCP alone, see
      # the note on that profile. If you plug the cable into a different NIC,
      # change `vlan.parent` to that device.
      networking.networkmanager.ensureProfiles.profiles = {
        vlan-pic = {
          connection = {
            id = "vlan-pic";
            type = "vlan";
            interface-name = "pic";
            autoconnect = "no";
            permissions = "user:kdn:;";
          };
          ethernet = { };
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
          ethernet = { };
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
          ethernet = { };
          vlan = {
            id = 3547;
            parent = "enp4s0";
          };
          ipv4 = {
            # DHCP only, with no static fallback. drek's pool includes .32, so the static
            # fallback this profile used to carry was not safe: on 2026-09-12 a webcam held
            # .32 (PTR `preorder-onlooker.lan.drek.net.int.kdn.im`). Reach oams here by the
            # `lan.drek` FQDN, which follows the lease, and add a static address back only
            # after drek reserves one outside the pool.
            method = "auto";
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
          system.nixos.tags = [ "vfio" ];
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

      # This host accepts builds from other machines, so it trusts the build-farm clients'
      # signing keys (oams-1, ...). A client that only *uses* builders must not.
      kdn.nix.remote-builder.trustClientSigningKeys = true;
    }
    {
      kdn.fs.zfs.containers.fsname = "oams-main/containers/storage";
      # The rootless store has its own `fs/home/kdn/.local/share/containers` dataset (see
      # `hosts/oams/disko.nix`), so it needs no `kdn.disks.persist` write. `null` keeps the
      # module from adding one. That bucket would be inert here anyway: this host sets
      # `kdn.fs.disko.luks-zfs.enable`, which is mutually exclusive with `kdn.disks.enable`, so
      # `preservation.enable` is false and no bucket reaches `preservation.preserveAt`. The
      # dataset, not this option, is what survives a rollback.
      kdn.virtualisation.containers.storage.rootlessPersistBase = null;
    }
    {
      kdn.services.samba.enable = true;
    }
    {
      security.sudo.wheelNeedsPassword = false;
    }
    {
      # rosec: a Secret Service daemon whose store is the sops-encrypted file tree under Nextcloud.
      # The store, the age identity and the unattended YubiKey recipient (PIV slot 3, PIN never,
      # touch never) were proven on this host on 2026-11-14 — see
      # docs/tasks/2026-11/keepassxc-to-rosec-migration/.
      #
      # `enable` stays FALSE: KeePassXC claims `org.freedesktop.secrets` on this host, and two units
      # cannot hold one bus name. The migration task flips this one line once its entries moved and
      # the KDBX provider is retired:
      #
      #     kdn.services.rosec.enable = true;
      #
      # The conflict report is independent: it reads the store, not the daemon, so it may run now.
      kdn.services.rosec = {
        enable = false;
        providers.sops = {
          path = "~/Nextcloud/drag0nius@nc.nazarewk.pw/important/rosec-storage";
          key_file = "~/.config/sops/age/keys.txt";
          # The `&yk-oams-unattended` recipient, line 3 of ~/.config/sops/age/keys.txt. It can add
          # access to a file, never narrow the recipients already written into a header.
          age_recipient = "age1yubikey1q25g9xpunct74wnn29dgcgep78q666dkhpfg2flltg92fvyrew02j28464d";
        };
        ssh_fuse = false;
        conflictNotification = {
          enable = true;
          # The host runs sway with swaync, so both the desktop notification and the control-centre
          # poke work.
          notify = true;
          swaync = true;
        };
      };
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
    {
      kdn.certificates.repoRoot = kdnConfig.self;
      kdn.certificates.certs.zellij-web = {
        ca = "kdn";
        type = "tls-server";
        commonName = "oams.priv.nb.net.int.kdn.im";
        sans = [
          "oams.priv.nb.net.int.kdn.im"
          "llama-swap.oams.priv.nb.net.int.kdn.im"
        ];
        directory = "hosts/oams/certs";
        certFile = "zellij.pub";
        keyFile = "zellij.key";
        keySource = "managed";
        owner = "kdn";
      };

      # The SSH host certificate. `principals` names every form a client may connect
      # with: the short name (what the `kdn-*` dispatcher checks through `HostKeyAlias`)
      # and each FQDN. See hosts/brys/ssh-ca.nix for the same shape.
      kdn.certificates.certs.ssh-host-oams = {
        ca = "kdn";
        type = "ssh-host";
        commonName = "oams";
        principals = (import ../../data/net/ssh-host-identities.nix).oams.names;
        directory = "hosts/oams/certs";
        certFile = "ssh_host_ed25519-cert.pub";
        keyFile = "ssh_host_ed25519_key";
        keySource = "managed";
      };

      # The post-quantum identity, offered IN ADDITION to ed25519, never instead.
      kdn.certificates.certs.ssh-host-oams-pq = {
        ca = "kdn";
        type = "ssh-host";
        commonName = "oams";
        principals = (import ../../data/net/ssh-host-identities.nix).oams.names;
        directory = "hosts/oams/certs";
        certFile = "ssh_host_mldsa44_ed25519-cert.pub";
        keyFile = "ssh_host_mldsa44_ed25519_key";
        keyType = "mldsa44-ed25519";
        keySource = "managed";
      };
    }
    {
      kdn.programs.zellij.web = {
        enable = true;
        bindAddress = "0.0.0.0";
        port = 8082;
        certFile = config.kdn.certificates.certs.zellij-web.certPath;
        keyFile = config.kdn.certificates.certs.zellij-web.keyPath;
        user = "kdn";
        firewallInterfaces = [ "nb-priv" ];
      };
    }
    {
      # oams tracks the newest Rambox Linux release from `packages/rambox`
      # (nixpkgs' wrapper, version bumped). See that package for the
      # version/hash to bump.
      kdn.apps."rambox".package.original = pkgs.kdn.rambox;
    }
  ];
}

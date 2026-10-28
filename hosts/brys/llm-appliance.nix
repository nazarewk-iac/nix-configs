# Shared body of the brys LLM-only boot entry (`specialisation.llms`).
#
# brys has one boot-selected appliance entry, `inheritParentConfig = false`, so
# it is a clean top-level with the desktop/workstation/gaming profiles left out.
# It used to be four (`llm-ds4`, `llm-small`, `llm-qwen`, `llms-frontier`); the
# split existed because a llama.cpp router could hold one model, and llama-swap
# removed that limit. One entry now serves the whole fleet: a frontier swap is a
# model swap, not a reboot.
#
# BOOT-SELECTED ONLY, NEVER ACTIVATED via switch-to-configuration. Kernel tuning
# and the ZFS ARC cap only apply on a cold boot.
{
  lib,
  pkgs,
  kdnConfig,
  tag,
  banner,
  llm,
  # Extra NixOS config merged last, for a single specialisation's own runtime
  # bits (for example the Vulkan graphics stack and the device-selection env).
  # Defaults to empty, so the other entries are unaffected.
  extraConfig ? { },
}:
{
  imports = [
    kdnConfig.self.nixosModules.default
    # LLM serving via the den `llm` aspect (llama-server router mode, TLS behind
    # Caddy); `llm.slot` supplies the `kdn.llm.local` data, and `llm.nixos` the
    # host-side secrets and model persistence.
    llm.slot
    llm.nixos
    # The SSH host certificate, the CA DAG and the `ssh-ca` aspect. Shared with
    # the main profile via ./ssh-ca.nix, so every brys boot presents the host
    # certificate and accepts CA user certificates.
    ./ssh-ca.nix
  ]
  ++ kdnConfig.self.denLib.imports {
    class = "nixos";
    aspects = [ "llm" ];
  }
  # The LLM tuning both consumers share: ARC cap, THP, NUMA, the sysctl floor and the
  # governor as a soft default. The appliance adds its core reservation on top.
  ++ [ ./llm-tuning-shared.nix ];

  config = lib.mkMerge [
    # ---- Boot as a minimal appliance ---------------------------------------
    {
      system.nixos.tags = [ tag ];
      system.stateVersion = "24.11";
      systemd.defaultUnit = lib.mkForce "multi-user.target";

      # Baseline gives the kdn user, fish, SSH, and the minimal headless base.
      # Nothing from workstation/gaming/desktop/sway/gaming is enabled here.
      kdn.profile.machine.baseline.enable = true;

      # kdn / linux fundamentals.
      kdn.enable = true;
      kdn.hostName = "brys";
      networking.hostId = "0a989258"; # ZFS requirement (same as main brys)
      kdn.locale.enable = true;

      home-manager.sharedModules = [ { home.stateVersion = "24.11"; } ];
      home-manager.users."kdn".home.stateVersion = "24.11";
    }

    # ---- Hardware (CPU + disks/LUKS, same as main brys) --------------------
    {
      kdn.hw.cpu.amd.enable = true;
      kdn.disks.enable = true;
      kdn.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04LZCR91M8UZPJW8-0:0";
      kdn.disks.luks.volumes."vp4300-brys" = {
        targetSpec.path = "/dev/disk/by-id/nvme-nvme.1e4b-5650343330304c45444242323333343032303433-5669706572205650343330304c20325442-00000001";
        uuid = "cbfe2928-2249-47fa-a48f-7c53c53a05d4";
        headerSpec.partNum = 2;
      };
      kdn.disks.luks.volumes."px700-brys" = {
        targetSpec.path = "/dev/disk/by-id/nvme-nvme.1e4b-473342303335383134-53534450522d50583730302d3032542d3830-00000001";
        uuid = "53513d1d-233f-4c6b-b1ea-eeb40062e580";
        headerSpec.partNum = 3;
      };
      boot.initrd.availableKernelModules = [
        "mt7921e"
        "r8169"
        "igb"
      ];
    }

    # ---- Networking (reachable the same way as main brys) ------------------
    {
      kdn.networking.enable = true;
      kdn.networking.iface.default = "kdn-eth-2g";
      kdn.networking.ifaces."kdn-eth-2g".selector.mac = "04:42:1a:ed:8b:03";
      kdn.networking.ifaces."kdn-eth-2g".dynamicIPClient = true;
      kdn.networking.ifaces."kdn-eth-2g".metric = 100;

      # Same VLAN reachability as the main host (drek/pic/mgmt), so SSH and
      # the LLM endpoint stay reachable from the usual networks.
      kdn.networking.vlans."drek".id = 3547;
      kdn.networking.vlans."drek".parent = "kdn-eth-2g";
      kdn.networking.ifaces."drek".dynamicIPClient = true;
      kdn.networking.ifaces."drek".metric = 900;
      kdn.networking.ifaces."drek".address.internal4 = "192.168.41.31/24";

      kdn.networking.vlans."pic".id = 1859;
      kdn.networking.vlans."pic".parent = "kdn-eth-2g";
      kdn.networking.ifaces."pic".dynamicIPClient = true;
      kdn.networking.ifaces."pic".metric = 1000;
      kdn.networking.ifaces."pic".address.internal4 = "10.92.0.5/24";
      kdn.networking.ifaces."pic".address.internal6 = "fd12:ed4e:366d:eb17:3c91:247b:a473:442/64";

      kdn.networking.vlans."mgmt".id = 946;
      kdn.networking.vlans."mgmt".parent = "kdn-eth-2g";
      kdn.networking.ifaces."mgmt".dynamicIPClient = true;
      kdn.networking.ifaces."mgmt".metric = 1100;
      kdn.networking.ifaces."mgmt".address.internal4 = "192.168.252.32/24";

      # systemd-networkd is the authoritative provider; drop NM's wait-online
      # so network-online.target settles (same fix as the main host).
      systemd.services."NetworkManager-wait-online" = {
        wantedBy = lib.mkForce [ ];
        requiredBy = lib.mkForce [ ];
      };
    }

    # ---- Secrets / LLM wiring -------------------------------------------
    # The LLM sops file, the model persistence directory and the leaf-key
    # service are shared with the main brys profile via ./llm.nix (imported
    # above).
    {
      security.sudo.wheelNeedsPassword = false;
    }

    # ---- Strip everything non-mandatory --------------------------------
    {
      zramSwap.enable = lib.mkForce false;
      services.bpftune.enable = lib.mkForce false;

      # Not needed headless / for serving.
      documentation.enable = lib.mkForce false;
      services.avahi.enable = lib.mkForce false;
      services.printing.enable = lib.mkForce false;
      hardware.bluetooth.enable = lib.mkForce false;

      # Leave only mandatory services on: openssh (baseline), caddy,
      # llama-cpp, kdn-llm-proxy-lan, kdn-llm-download.target.
    }

    # ---- Pre-login banner on tty1 (getty /etc/issue) -------------------
    {
      environment.etc."issue".text = lib.mkForce banner;
      # Show it even before login on the virtual consoles.
      environment.etc."issue.d".text = "";
      systemd.tmpfiles.rules = [ ];
    }

    # ---- Performance tuning: the appliance-only delta --------------------
    #
    # The settings that are correct on BOTH consumers live in ./llm-tuning-shared.nix:
    # the ZFS ARC cap, `transparent_hugepage=madvise`, `numa_balancing=disable`, the
    # sysctl floor and the performance governor as a soft default. This block adds only
    # what an appliance may take and a desktop may not.
    {
      # Core reservation. This is the one genuinely divisive setting: `isolcpus` removes
      # cores from the scheduler, so every ordinary task is confined to what is left.
      # That is correct for a box that exists to serve models and disqualifying for a
      # desktop, which is exactly why it is here and not in the shared file.
      #
      # On this CPU (Ryzen 9 5950X: 16 physical cores, 32 logical) the isolated set is
      # physical cores, so isolation holds whether or not SMT is on.
      boot.kernelParams = [
        "isolcpus=1-15"
        "nohz_full=1-15"
        "rcu_nocbs=1-15"
        # Never let a core drop into a deep C-state: wake latency on a bandwidth-bound
        # decode loop is worse than the idle power.
        "processor.max_cstate=1"
        "amd_pstate=active"
      ];

      # `mkForce` because the shared file sets a soft default, and an appliance overrides it.
      powerManagement.cpuFreqGovernor = lib.mkForce "performance";

      # Memory behaviour for a 95 GiB `mmap` and no interactive user: never swap (an OOM is
      # better than a 40 GB swap-in), overcommit freely, tolerate large writeback bursts.
      boot.kernel.sysctl = {
        "vm.swappiness" = 0;
        "vm.overcommit_memory" = 1;
        "vm.dirty_ratio" = 40;
        "vm.dirty_background_ratio" = 10;
      };
    }

    # ---- Entry-specific extras -------------------------------------------
    extraConfig
  ];
}

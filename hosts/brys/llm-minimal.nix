# Minimal LLM-only specialisation for brys.
#
# BOOT-SELECTED ONLY, NEVER ACTIVATED via switch-to-configuration. This is a
# clean top-level (`inheritParentConfig = false`) boot entry that re-declares
# the minimum needed to boot the same hardware and serve local LLMs with
# as little RAM/CPU/service overhead as possible, so the model has the whole
# machine. The default "brys" boot entry is unaffected.
#
# The kdn universal base + the thick host profiles (workstation/gaming/
# desktop/sway/EDID/nanokvm) are NOT imported here. `kdn.profile.machine
# .baseline` is reused because it already declares the kdn user, SSH, fish,
# and the minimal headless base.
{
  lib,
  config,
  pkgs,
  kdnConfig,
  ...
}:
let
  slots = kdnConfig.self.mkSlots {
    inherit pkgs;
    # LLM serving is the whole point of this boot entry: same slot wiring as
    # the main brys config (models, DSpark draft, download, caddy/proxy).
    kdn.llm.local.enable = true;
    kdn.llm.local.modelsDir = "/var/lib/kdn/llms/models";
    kdn.llm.local.download.tokenFile = "/run/configs/llms/huggingface/token";
    kdn.llm.local.domain = "brys.lan.etra.net.int.kdn.im";
    kdn.llm.local.certs.certFile = "${kdnConfig.self}/hosts/brys/certs/llm.pub";
    kdn.llm.local.certs.keyFile = "/run/secrets/kdn/brys/llm.key";
    kdn.llm.local.certs.sans = [
      "brys.lan.etra.net.int.kdn.im"
      "brys.lan.drek.net.int.kdn.im"
      "brys.priv.nb.net.int.kdn.im"
    ];
    kdn.llm.local.apiKeyDir = "/run/configs/llms/llama-server/api-keys";
    kdn.llm.local.download.mode = "fast-polite";
    kdn.llm.local.download.xetConcurrency = 8;
    # Same models/per-model perf as the main host, but DeepSeek biased to its
    # verified-working 256K context (nothing else competes for RAM here).
    kdn.llm.local.models = {
      deepseek-v4-flash = {
        enable = true;
        hfRepo = "unsloth/DeepSeek-V4-Flash-GGUF";
        hfFile = "UD-IQ3_XXS/DeepSeek-V4-Flash-UD-IQ3_XXS-00001-of-00004.gguf";
        download.glob = "UD-IQ3_XXS/DeepSeek-V4-Flash-UD-IQ3_XXS-*.gguf";
        aliases = ["frontier"];
        perf.contextSize = 262144;
        perf.reasoning = "off";
        perf.specType = "draft-dspark";
        perf.cpuRange = "1-15";
        perf.cpuStrict = true;
        perf.threads = 15;
        draft = {
          enable = true;
          hfRepo = "unsloth/DeepSeek-V4-Flash-0731-GGUF";
          hfFile = "dspark-DeepSeek-V4-Flash-0731-Q8_0.gguf";
        };
      };
    };
  };
in {
  imports = [
    kdnConfig.self.nixosModules.default
    slots.config.nixos
  ];

  config = lib.mkMerge [
    # ---- Boot as a minimal appliance ---------------------------------------
    {
      system.nixos.tags = ["llm-minimal"];
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

      home-manager.sharedModules = [{home.stateVersion = "24.11";}];
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
        wantedBy = lib.mkForce [];
        requiredBy = lib.mkForce [];
      };
    }

    # ---- Secrets (LLM token + caddy leaf key, same as main brys) ----------
    {
      security.sudo.wheelNeedsPassword = false;

      kdn.security.secrets.sops.files."llms" = {
        sopsFile = "${kdnConfig.self}/llms.nonsensitive.sops.yaml";
        basePath = "/run/configs/llms";
        sops.mode = "0444";
      };

      # Raw-decrypt the LLM leaf PRIVATE key into /run/secrets before Caddy.
      systemd.services.kdn-llm-leaf-key = {
        description = "Decrypt brys LLM leaf private key into /run/secrets";
        wantedBy = ["caddy.service"];
        before = ["caddy.service"];
        path = [pkgs.sops pkgs.coreutils];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          Group = "root";
        };
        script = ''
          set -euo pipefail
          mkdir -p /run/secrets/kdn/brys
          ${pkgs.sops}/bin/sops decrypt --output-type binary \
            ${kdnConfig.self}/hosts/brys/certs/llm.key.sops \
            > /run/secrets/kdn/brys/llm.key
          chmod 0400 /run/secrets/kdn/brys/llm.key
        '';
      };

      kdn.disks.persist."usr/data".directories = [
        {
          directory = "/var/lib/kdn/llms/models";
          mode = "0755";
        }
      ];
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
      environment.etc."issue".text = lib.mkForce ''
        \e[1;33m============================================================\e[0m
        \e[1;31m  Minimal LLM-ONLY instance  (brys / llm-minimal)\e[0m
        \e[1;33m============================================================\e[0m
        Booted into the isolated DeepSeek-serving topology. Freeing the whole
        machine for local LLM inference; no desktop, no workstation services.

        DeepSeek V4 Flash @ 256K ctx, DSpark draft, reasoning off.
        \e[1;33m============================================================\e[0m
        Login with your usual kdn/SSH credentials. Use the normal host to do
        anything else.
      '';
      # Show it even before login on the virtual consoles.
      environment.etc."issue.d".text = "";
      systemd.tmpfiles.rules = [];
    }

    # ---- Performance tuning for CPU-only inference ----------------------
    {
      boot.kernelParams = [
        "isolcpus=1-15"
        "nohz_full=1-15"
        "rcu_nocbs=1-15"
        "transparent_hugepage=madvise"
        "processor.max_cstate=1"
        "amd_pstate=active"
        "numa_balancing=disable"
        "quiet"
        "loglevel=3"
      ];
      powerManagement.cpuFreqGovernor = lib.mkForce "performance";
      boot.kernel.sysctl = {
        "vm.swappiness" = 0;
        "vm.overcommit_memory" = 1;
        "vm.compaction_proactiveness" = 0;
        "vm.dirty_ratio" = 40;
        "vm.dirty_background_ratio" = 10;
        "fs.file-max" = 1048576;
      };
      # Keep root on disk (not tmpfs) for this build-only minimal entry so it
      # is guaranteed bootable; the reduction comes from services/desktop off.
    }
  ];
}

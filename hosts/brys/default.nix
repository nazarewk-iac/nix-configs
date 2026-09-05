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

    # Trust the KDN CA (data/ca.pub) system-wide; reference the offline CA key path.
    kdn.ca.kdn.enable = true;
    kdn.ca.kdn.certFile = "${kdnConfig.self}/data/ca.pub";
    kdn.ca.kdn.keySopsFile = "${kdnConfig.self}/data/ca.key.sops";

    # Local LLM serving (llama-server router mode, TLS behind caddy). Models are
    # registered under kdn.disks.persist."usr/data" further below; the slot
    # receives only the path and the cert/key path fragments.
    kdn.llm.local.enable = true;
    kdn.llm.local.modelsDir = "/var/lib/kdn/llms/models";
    # HF token for faster/authenticated downloads, wired via sops below to
    # /run/configs/llms/huggingface/token.
    kdn.llm.local.download.tokenFile = "/run/configs/llms/huggingface/token";
    # LAN endpoint hostname + leaf cert paths (signed by the KDN CA). The public
    # cert is referenced from the repo store; the private key is raw sops-decrypted
    # on brys into /run/secrets (see the kdn-llm-leaf-key service) and loaded into
    # Caddy via LoadCredential.
    kdn.llm.local.domain = "brys.lan.etra.net.int.kdn.im";
    kdn.llm.local.certs.certFile = "${kdnConfig.self}/hosts/brys/certs/llm.pub";
    kdn.llm.local.certs.keyFile = "/run/secrets/kdn/brys/llm.key";
    kdn.llm.local.certs.sans = [
      "brys.lan.etra.net.int.kdn.im"
      "brys.lan.drek.net.int.kdn.im"
      "brys.priv.nb.net.int.kdn.im"
    ];
    kdn.llm.local.apiKeyDir = "/run/configs/llms/llama-server/api-keys";
    # Global download: fast-polite keeps Xet enabled but with a configurable,
    # capped concurrency. Tuned to target roughly 500-700 Mbit/s; raise/lower
    # `xetConcurrency` to trade speed vs network aggression. Downloads run
    # sequentially in the host network namespace.
    kdn.llm.local.download.mode = "fast-polite";
    kdn.llm.local.download.xetConcurrency = 8;
    kdn.llm.local.models = {
      qwen3-30b-a3b = {
        enable = true;
        hfRepo = "Qwen/Qwen3-30B-A3B-GGUF";
        hfFile = "Qwen3-30B-A3B-Q4_K_M.gguf";
        aliases = ["fast"];
        perf.contextSize = 131072;
      };
      qwen3-next-80b = {
        enable = true;
        hfRepo = "unsloth/Qwen3-Next-80B-A3B-Instruct-GGUF";
        hfFile = "Qwen3-Next-80B-A3B-Instruct-Q4_K_M.gguf";
        aliases = ["balanced"];
        perf.contextSize = 131072;
      };
      # deepseek-v4-flash: big, multi-shard, frontier quality. Slow to load.
      # download.glob fetches all 4 shards (~104 GB); llama serves shard 00001.
      # Keep it loaded for 24h (default is 1h) — it takes minutes to load, so
      # hold it in RAM rather than churning the swap frequently.
      # Shard 00001 is legitimately small (~5 MB — it is the split descriptor +
      # mmap header); llama mmaps shards 02-04 for the full weights. The DSpark
      # draft (~10.9 GB) is downloaded through the same kdn-llm-download
      # mechanism and feeds model-draft (spec-type draft-dspark).
      deepseek-v4-flash = {
        enable = true;
        hfRepo = "unsloth/DeepSeek-V4-Flash-GGUF";
        hfFile = "UD-IQ3_XXS/DeepSeek-V4-Flash-UD-IQ3_XXS-00001-of-00004.gguf";
        download.glob = "UD-IQ3_XXS/DeepSeek-V4-Flash-UD-IQ3_XXS-*.gguf";
        aliases = ["frontier"];
        # Try 256K MLA KV (≈22.8 GB) first per operator preference; if it
        # thrash-swaps (model 103 + draft 11 + KV 22.8 ≈ 140 GB > 128 GB),
        # fall back to 131072 (128K, KV ≈ 11.4 GB → ≈128 GB total).
        perf.contextSize = 262144;
        perf.reasoning = "off";
        perf.specType = "draft-dspark";
        draft = {
          enable = true;
          hfRepo = "unsloth/DeepSeek-V4-Flash-0731-GGUF";
          hfFile = "dspark-DeepSeek-V4-Flash-0731-Q8_0.gguf";
        };
      };
      # Qwen3-235B split into 2 parts; download.glob fetches both. 64K ctx ≈
      # 25 GB KV, well within 128 GB.
      qwen3-235b = {
        enable = true;
        hfRepo = "mradermacher/Qwen3-235B-A22B-i1-GGUF";
        hfFile = "Qwen3-235B-A22B.i1-IQ2_M.gguf.part1of2";
        download.glob = "Qwen3-235B-A22B.i1-IQ2_M.gguf.part*";
        perf.contextSize = 65536;
      };
      # Qwen3-Coder-Next split into 4 shards; download.glob fetches all of them.
      qwen3-coder-next = {
        enable = true;
        hfRepo = "Qwen/Qwen3-Coder-Next-GGUF";
        hfFile = "Qwen3-Coder-Next-Q4_K_M/Qwen3-Coder-Next-Q4_K_M-00001-of-00004.gguf";
        download.glob = "Qwen3-Coder-Next-Q4_K_M/Qwen3-Coder-Next-Q4_K_M-*.gguf";
        perf.contextSize = 131072;
      };
      gpt-oss-120b = {
        enable = true;
        hfRepo = "unsloth/gpt-oss-120b-GGUF";
        hfFile = "gpt-oss-120b-F16.gguf";
      };
      phi-4 = {
        enable = true;
        hfRepo = "microsoft/phi-4-gguf";
        hfFile = "phi-4-Q4_K.gguf";
        # 16K is Phi-4's hard architectural context ceiling.
        perf.contextSize = 16384;
      };
    };
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
      kdn.hostName = "brys";

      system.stateVersion = "24.11";
      home-manager.sharedModules = [{home.stateVersion = "24.11";}];
      networking.hostId = "0a989258"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      kdn.profile.machine.workstation.enable = true;
      kdn.hw.gpu.amd.enable = true;
      kdn.hw.cpu.amd.enable = true;

      # CPU-only MoE inference is memory-bandwidth bound: keep all cores pinned
      # high. The default `powersave` governor ramps cores unevenly and roughly
      # halves throughput + adds ~45s to first token on DeepSeek V4 Flash
      # (verified: 6.25 tok/s / 1.06s TTFT vs 3.27 tok/s / 47s TTFT).
      powerManagement.cpuFreqGovernor = "performance";

      kdn.programs.photoprism.enable = false;

      kdn.profile.machine.gaming.enable = true;

      boot.initrd.availableKernelModules = [
        "mt7921e" # MEDIATEK Corp. MT7921K (RZ608) Wi-Fi 6E 80MHz
        "r8169" # Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller [10ec:8125] (rev 05)
        "igb" # Intel Corporation I211 Gigabit Network Connection [8086:1539] (rev 03)
      ];

      # enp5s0 is 1GbE
      #networking.interfaces.enp5s0.wakeOnLan.enable = true;
      # enp6s0 is 2.5GbE
      #networking.interfaces.enp6s0.wakeOnLan.enable = true;

      zramSwap.enable = lib.mkDefault true;
      zramSwap.memoryPercent = 50;
      zramSwap.priority = 100;

      # 12G was not enough for large rebuild
      boot.tmp.tmpfsSize = "32G";
    }
    {
      kdn.hw.edid.enable = true;
      hardware.display.outputs."DP-4" = {
        edid = "PG278Q_120.bin";
        mode = "e";
      };
    }
    /*
       {
      # automated unlock using Clevis through Tang server
      boot.initrd.network.flushBeforeStage2 = true;
      networking.interfaces.enp5s0.useDHCP = true;
      networking.interfaces.enp6s0.useDHCP = true;

      boot.initrd.network.enable = true; # this is systemd-networkd all he way through anyway
      boot.initrd.systemd.network.wait-online.enable = true;
      boot.initrd.systemd.network.wait-online.anyInterface = true;
      boot.initrd.systemd.network.wait-online.timeout = 15;

      #boot.initrd.clevis.useTang = true;
      #boot.initrd.clevis.devices."brys-main-crypted".secretFile = ./brys-main-crypted.jwe;
    }
    */
    {
      # TODO: those are unlocked automatically using TPM2, switch to etra (or k8s cluster) backed Clevis+Tang unlock
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
    }
    {
      kdn.hw.nanokvm.enable = true;
    }
    {
      kdn.desktop.sway.portals.debug = true;
    }
    {
      # VNC access over Netbird
      networking.firewall.interfaces."nb-priv".allowedTCPPorts = [
        5900
      ];
      networking.firewall.interfaces."nb-priv".allowedUDPPorts = [
        5900
      ];
    }
    {
      kdn.networking.enable = true;
      kdn.networking.debug = true;
      kdn.networking.iface.default = "kdn-eth-2g";

      # Fixing sporadic `network-online.target` stalls on rebuilds: the primary
      # link (kdn-eth-2g, default route) is managed by systemd-networkd and is
      # deliberately unmanaged in NetworkManager (only the autoconnect=false
      # gipe/talt/mokerlink profiles use NM). With both
      # `systemd-networkd-wait-online` and `NetworkManager-wait-online` wanted
      # by network-online.target, nm-online never sees a connection it manages
      # and can keep the target from settling during switch-triggered networkd
      # restarts, so dependent services (atuin-login, llm downloads) fail until
      # reboot. systemd-networkd is the authoritative provider, so drop NM's
      # wait-online; the target then only waits for the networkd-managed link.
      systemd.services."NetworkManager-wait-online" = {
        wantedBy = lib.mkForce [];
        requiredBy = lib.mkForce [];
      };

      kdn.networking.ifaces."kdn-eth-2g".selector.mac = "04:42:1a:ed:8b:03";
      kdn.networking.ifaces."kdn-eth-2g".dynamicIPClient = true;
      kdn.networking.ifaces."kdn-eth-2g".metric = 100;

      kdn.networking.ifaces."kdn-eth-1g".managed = false;
      kdn.networking.ifaces."kdn-eth-1g".selector.mac = "04:42:1a:ed:8b:04";

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

      kdn.networking.vlans."drek".id = 3547;
      kdn.networking.vlans."drek".parent = "kdn-eth-2g";
      kdn.networking.ifaces."drek".dynamicIPClient = true;
      kdn.networking.ifaces."drek".metric = 900;
      kdn.networking.ifaces."drek".address.internal4 = "192.168.41.31/24";
    }
    /*
    (let
      iface = "vm-nbt-1";
      microvmPersistNames = ["microvm"] ++ builtins.attrNames config.kdn.disks.base;
    in {
      systemd.network.networks."40-ethernet-2.5g" = {
        matchConfig.Name = [iface];
      };

      microvm.vms.nbt-1 = {
        autostart = true;
        restartIfChanged = true;
        specialArgs =
          kdn.configure {
            moduleType = "nixos";
          } {
            kdn.features.microvm-guest = true;
          };
        config = {
          imports = [
            kdn.self.nixosModules.default
          ];
          config = lib.mkMerge [
            {
              kdn.hostName = "brys-uvm-nbt-1";
              system.stateVersion = "25.05";
              home-manager.sharedModules = [{home.stateVersion = "25.05";}];
              networking.hostId = "fb6ff1fa"; # cut -c-8 </proc/sys/kernel/random/uuid
              kdn.security.secrets.enable = false;

              kdn.networking.netbird.clients.priv.enable = false;
            }
            {
              microvm.interfaces = [
                {
                  type = "tap";
                  id = iface;
                  mac = "42:e2:ce:6a:ce:c1";
                }
              ];
              systemd.network.enable = true;

              systemd.network.networks."20-lan" = {
                matchConfig.Type = "ether";
                networkConfig = {
                  DHCP = true;
                  IPv6AcceptRA = true;
                  LinkLocalAddressing = "ipv6";

                  IPv6PrivacyExtensions = true;
                  IPv6LinkLocalAddressGenerationMode = "stable-privacy";
                };
              };
            }
          ];
        };
      };
    })
    */
    {
      services.bpftune.enable = true;
    }
    {
      kdn.disks.nixBuildDir.type = "tmpfs";
      kdn.disks.nixBuildDir.tmpfs.size = "64G";
    }
    {
      networking.hosts."10.116.89.68" = ["gipe"];
      networking.networkmanager.ensureProfiles.profiles.gipe = {
        connection = {
          id = "gipe";
          type = "ethernet";
          interface-name = "enp7s0";
          autoconnect = false;
        };
        ethernet.mac-address = "04:42:1A:ED:8B:04";
        ipv4 = {
          method = "manual";
          address1 = "10.116.89.69/31";
          may-fail = false;
        };
        ipv6.method = "disabled";
      };
    }
    {
      networking.hosts."192.168.88.1" = ["talt-mgmt"];
      networking.networkmanager.ensureProfiles.profiles.talt-mgmt = {
        connection = {
          id = "talt-mgmt";
          type = "ethernet";
          interface-name = "enp7s0";
          autoconnect = false;
        };
        ethernet.mac-address = "04:42:1A:ED:8B:04";
        ipv4 = {
          method = "manual";
          address1 = "192.168.88.2/24";
          may-fail = false;
        };
        ipv6.method = "disabled";
      };
    }
    {
      networking.hosts."192.168.2.1" = ["mokerlink"];
      networking.networkmanager.ensureProfiles.profiles.mokerlink-switch = {
        connection = {
          id = "mokerlink-switch";
          type = "ethernet";
          interface-name = "enp7s0";
          autoconnect = false;
        };
        ethernet.mac-address = "04:42:1A:ED:8B:04";
        ipv4 = {
          method = "manual";
          address1 = "192.168.2.2/24";
          may-fail = false;
        };
        ipv6.method = "disabled";
      };
    }
    {
      # kdn.nix.remote-builder.localhost.publicHostKey = "??";
      kdn.nix.remote-builder.localhost.maxJobs = 12;
      kdn.nix.remote-builder.localhost.speedFactor = 32;
    }
    {
      security.sudo.wheelNeedsPassword = false;
    }
    {
      # Keep local LLM models on the persistent usr/data dataset.
      kdn.disks.persist."usr/data".directories = [
        {
          directory = "/var/lib/kdn/llms/models";
          # World-readable so any user (and llama-swap's DynamicUser) can read
          # the models; the download script keeps files 644 / dirs 755.
          mode = "0755";
        }
      ];
    }
    {
      # Shared /run/configs/llms secrets: HF token and llama-server API keys.
      # Decrypted to their full sops key paths under /run/configs/llms/. Shared
      # with the oams host (same mount point).
      kdn.security.secrets.sops.files."llms" = {
        sopsFile = "${kdnConfig.self}/llms.nonsensitive.sops.yaml";
        basePath = "/run/configs/llms";
        sops.mode = "0444";
      };
    }
    {
      # Raw-decrypt the brys LLM leaf PRIVATE key from hosts/brys/certs/llm.key.sops
      # into /run/secrets (root-only tmpfs) before Caddy starts. Uses the wrapped
      # `sops` (age identity auto-imported from brys' SSH host key). The pub cert is
      # referenced directly from the store (no decryption). Caddy loads the key via
      # LoadCredential (see the llm slot's caddy wiring).
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
    }
    {
      services.angrr.enable = false;
    }
    {
      # Boot-selectable minimal LLM-only entry. `inheritParentConfig = false`
      # gives it a clean top-level: only the disk/LUKS/networking/ssh/kdn-user
      # and the LLM slot, with desktop/workstation/gaming turned off, so DeepSeek
      # gets the whole machine. NEVER activate via switch-to-configuration —
      # select it from the bootloader; kernel tuning only applies on a cold boot.
      specialisation.llm-minimal = {
        inheritParentConfig = false;
        configuration = {
          imports = [
            ./llm-minimal.nix
          ];
        };
      };
    }
  ];
}

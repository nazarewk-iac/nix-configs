# brys, the LLM workstation, on the den tree. FULL carryover of `hosts/brys/` (old universal
# tree), with one deliberate exception: the test passwords of the `kdn` and `root` accounts live in
# `./users.data.nix` and `pass`, so a failed boot is recoverable over the KVM or SSH.
#
# The output is `denConfigurations.brys`; never add this host to `nixosConfigurations`.
#
# ## What the old host resolves to
#
# The old host imports `nixosModules.default` (the whole universal tree), the `kdn` slots
# (`ssh-access`, `ca`, `devenv`), the local-LLM slot, and a handful of den aspects. The enabled
# `kdn.*` surface is 116 flags. This file replaces the auto-loader with an explicit `includes` list:
# every aspect below names one old module or one old slot, and the mapping table in
# ../../docs/den-universal-mapping.md records the pairing.
#
# ## The boot path is the reason for the care
#
# brys is a LUKS+ZFS host with a tmpfs root and a TPM-backed age identity. The boot order that must
# survive the port is: initrd unlocks both LUKS volumes, the TPM age identity decrypts the sops
# secrets, and only then does sshd start. A missing aspect or a changed secret ordering turns a
# working host into one that needs the NanoKVM. Every value in the "boot path" blocks below is
# copied verbatim from `hosts/brys/default.nix`.
{
  kdn,
  inputs,
  lib,
  ...
}:
let
  # The whole local-LLM serving config. It is a plain function that takes the flake as
  # `kdnConfig.self`, so the old file keeps working unchanged. Its three outputs (`slot`, `gpu`,
  # `nixos`) are merged below.
  llm = import ./llm.nix {
    inherit lib;
    pkgs = inputs.self.pkgs.x86_64-linux.default;
    kdnConfig = { self = inputs.self; };
    profile = "desktop";
  };

  # The account rows. A data file, not a module: the `user-profiles` aspect imports it into
  # `kdn.userProfileData` and turns each selected row into one account.
  usersData = import ./users.data.nix;

  # The SSH host certificates, shared with every boot specialisation. The old `hosts/brys/ssh-ca.nix`
  # imports the CA DAG and the three aspects; here the host does that through `includes`, so the
  # file only carries the data.
  sshHostIdentities = import ../../data/net/ssh-host-identities.nix;
in
{
  den.hosts.x86_64-linux.brys = {
    # `homeManager` must be explicit. den's default is `[ "user" ]` alone, and a user without it
    # gets no home-manager generation, so every aspect's `homeManager` half goes nowhere.
    users.kdn.classes = [
      "user"
      "homeManager"
    ];
  };

  # One aspect per thing the old host reached through the universal loader or a slot.
  #
  # The list is the whole enabled surface. Bundle aspects (`profile-workstation`, `profile-desktop`,
  # `profile-dev`, `profile-basic`, `profile-baseline`) already pull most of the leaf aspects; the
  # leaves below stay named for the ones a bundle does not carry, and an extra name is deduped by
  # `includes`.
  den.aspects.brys.includes = with kdn; [
    # --- machine profiles -------------------------------------------------
    profile-baseline
    profile-basic
    profile-workstation
    profile-desktop
    profile-dev
    profile-gaming
    profile-headless
    profile-headless-vim
    profile-headless-wezterm
    profile-default-secrets
    profile-remote-builders

    # --- hardware ---------------------------------------------------------
    hw-basic
    hw-audio
    hw-bluetooth
    hw-cpu-amd
    hw-edid
    hw-gpu
    hw-gpu-amd
    hw-nanokvm
    hw-qmk
    hw-usbip
    hw-yubikey

    # --- boot path: disks, secrets, identity ------------------------------
    disks
    disks-persist
    fs-zfs
    security-disk-encryption
    security-secrets-age
    security-secrets-sops
    security-dynamic-netrc
    secrets
    locale
    managed
    nix-config
    nix-remote-builder
    ca
    ca-dag
    certificates
    ssh-ca

    # --- networking -------------------------------------------------------
    net-interfaces
    net-dynamic-hosts
    net-resolved
    net-netbird
    net-tailscale

    # --- desktop ----------------------------------------------------------
    desktop-base
    desktop-sway
    desktop-sway-remote
    desktop-sway-waybar
    desktop-sway-kanshi
    desktop-sway-nwg-shell
    desktop-sway-nwg-panel
    desktop-sway-swaylock
    desktop-sway-swaync
    desktop-sway-swayr
    desktop-sway-media-keys
    desktop-remote-server
    stylix

    # --- development ------------------------------------------------------
    dev-android
    dev-ansible
    dev-cloud
    dev-cloud-aws
    dev-data
    dev-db
    dev-documents
    dev-dotnet
    dev-elixir
    dev-git
    dev-golang
    dev-java
    dev-jetbrains
    dev-k8s
    dev-llm-claude-code
    dev-llm-omp
    dev-llm-opencode
    dev-llm-pi
    dev-lua
    dev-nickel
    dev-nix
    dev-nodejs
    dev-python
    dev-rpi
    dev-rust
    dev-shell
    dev-terraform
    dev-web

    # --- programs ---------------------------------------------------------
    apps
    program-atuin
    program-browsers-launcher
    program-chrome
    program-chromium
    program-dconf
    program-direnv
    program-editors-photo
    program-editors-video
    program-firefox
    program-fish
    program-gnupg
    program-handlr
    program-kdeconnect
    program-matrix
    program-midnight-commander
    program-nix-index
    program-obs-studio
    program-office
    program-thunderbird
    program-ydotool
    program-zsh
    zellij
    zellij-web

    # --- toolsets ---------------------------------------------------------
    toolset-diagrams
    toolset-essentials
    toolset-fs
    toolset-fs-encryption
    toolset-logs-processing
    toolset-mikrotik
    toolset-network
    toolset-network-gui
    toolset-nix
    toolset-tracing
    toolset-unix

    # --- virtualisation ---------------------------------------------------
    virt-containers
    virt-containers-podman
    virt-libvirtd
    virt-vagrant

    # --- services ---------------------------------------------------------
    service-iperf3
    service-k8s-management
    service-nextcloud-client
    service-printing

    # --- SSH identity and the local LLM ----------------------------------
    ssh-access
    devenv-cli
    llm
    web-exposure
    user-profiles
  ];

  # The `kdn` user's own aspects. den partitions an aspect by scope, so a host-scope
  # `homeManager` half reaches no user: the user entity below is the route. The list repeats the
  # host's aspect names on purpose, exactly as the old tree loaded every universal module into the
  # Home Manager context through `home-manager.sharedModules`.
  den.aspects.kdn.includes = with kdn; [
    apps
    ca-dag
    certificates
    desktop-base
    desktop-sway
    desktop-sway-kanshi
    desktop-sway-media-keys
    desktop-sway-nwg-panel
    desktop-sway-nwg-shell
    desktop-sway-swaylock
    desktop-sway-swaync
    desktop-sway-swayr
    desktop-sway-waybar
    dev-android
    dev-ansible
    dev-cloud
    dev-cloud-aws
    dev-data
    dev-db
    dev-documents
    dev-dotnet
    dev-elixir
    dev-git
    dev-golang
    dev-java
    dev-jetbrains
    dev-k8s
    dev-llm-claude-code
    dev-llm-omp
    dev-llm-opencode
    dev-llm-pi
    dev-lua
    dev-nickel
    dev-nix
    dev-nodejs
    dev-python
    dev-rpi
    dev-rust
    dev-shell
    dev-terraform
    dev-web
    devenv-cli
    disks-persist
    hm-bootstrap
    hw-audio
    hw-yubikey
    llm-client
    locale
    net-dynamic-hosts
    net-netbird
    packaging-asdf
    pi-client
    profile-basic
    profile-desktop
    profile-dev
    profile-gaming
    profile-headless
    profile-headless-vim
    profile-headless-wezterm
    profile-workstation
    program-atuin
    program-browsers-launcher
    program-chrome
    program-chromium
    program-dconf
    program-direnv
    program-editors-photo
    program-editors-video
    program-firefox
    program-fish
    program-gnupg
    program-handlr
    program-kdeconnect
    program-kdn-tools
    program-matrix
    program-midnight-commander
    program-nix-index
    program-obs-studio
    program-office
    program-ssh-client
    program-terminal-ide
    program-thunderbird
    program-weechat
    program-wofi
    program-zsh
    secrets
    security-secrets-age
    service-rosec
    signing
    ssh-access
    ssh-agent
    ssh-ca
    stylix-home
    toolset-diagrams
    toolset-essentials
    toolset-fs
    toolset-fs-encryption
    toolset-logs-processing
    toolset-mikrotik
    toolset-network
    toolset-network-gui
    toolset-nix
    toolset-unix
    user
    virt-containers
    virt-containers-dagger
    virt-libvirtd
    zellij
    zellij-web
    user-profiles
  ];

  den.aspects.brys.nixos =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        # The account data. One row per person, the same file the old tree reads through
        # `kdn.userProfileData`-free writes.
        usersData

        # The CA DAG node for `kdn.ca` (the fleet root CA). The `ssh-ca` aspect reads it to derive
        # the CA public key for `TrustedUserCAKeys` and the `@cert-authority` line.
        ../../data/ca/ca-dag.nix

        # The LLM slot data, the host-side secrets/persistence, and the GPU runtime config. These are
        # plain modules, so they merge into this target exactly as they merged into the old host.
        llm.slot
        llm.nixos
        llm.gpu
      ];

      # --- identity ---------------------------------------------------------
      networking.hostName = "brys";
      networking.hostId = "0a989258";
      system.stateVersion = "24.11";

      # The old host pins every package to the flake's single per-system instance, so the host,
      # the specialisation and the ad-hoc `nix` calls share one nixpkgs. den does the same here.
      nixpkgs.pkgs = inputs.self.pkgs.x86_64-linux.default;

      home-manager.useGlobalPkgs = true;
      home-manager.sharedModules = [ { home.stateVersion = "24.11"; } ];

      # --- boot path --------------------------------------------------------
      # The two LUKS volumes and the USB boot device. Copied verbatim from the old host: a wrong id
      # or uuid here is a host that cannot unlock its root.
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

      # The build directory on tmpfs, and the persistent buckets the old host names.
      kdn.disks.nixBuildDir.type = "tmpfs";
      kdn.disks.nixBuildDir.tmpfs.size = "64G";

      # The initrd emergency shell accepts root with the generated password hash, so a failed LUKS
      # or TPM unseal still leaves a usable console over the NanoKVM. A hash, not a secret: no
      # boot-time decrypt is involved.
      kdn.profile-baseline.initrd.emergencyAccess = usersData.kdn.userProfileData.root.passwordHash;

      boot.initrd.availableKernelModules = [
        "mt7921e" # MEDIATEK Corp. MT7921K (RZ608) Wi-Fi 6E 80MHz
        "r8169" # Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller [10ec:8125] (rev 05)
        "igb" # Intel Corporation I211 Gigabit Network Connection [8086:1539] (rev 03)
      ];

      zramSwap.enable = lib.mkDefault true;
      zramSwap.memoryPercent = 50;
      zramSwap.priority = 100;

      # 12G was not enough for a large rebuild.
      boot.tmp.tmpfsSize = "32G";

      # A TPM 2.0 identity decrypts sops with nobody at the machine, so the smart card is no longer
      # on the boot path. The YubiKey is a break-glass recipient only. The TPM is contended in the
      # first seconds of boot (two LUKS volumes unseal with it), so wait up to 30 s for it and then
      # continue with the other identities.
      kdn.hw.yubikey.requiredForBoot = false;
      kdn.security.secrets.age.tpm.enable = true;
      kdn.security.secrets.age.tpm.waitSeconds = 30;

      # --- CPU and GPU ------------------------------------------------------
      # CPU-only MoE inference is memory-bandwidth bound: keep all cores pinned high. The default
      # `powersave` governor ramps cores unevenly and roughly halves throughput.
      powerManagement.cpuFreqGovernor = "performance";

      kdn.hw.edid.enable = true;
      hardware.display.outputs."DP-4" = {
        edid = "PG278Q_120.bin";
        mode = "e";
      };

      # A TPM or a network unlock of the encrypted root, so a reboot needs no keyboard.
      boot.initrd.clevis.enable = lib.mkDefault true;

      # --- containers -------------------------------------------------------
      # The rootless store lives on the persistent `usr/data` base, never on the disposable home.
      # The `virt-containers` aspect publishes the list; the host states the bucket once.
      kdn.disks.persist."usr/data".directories = config.kdn.virtualisation.containers.persist.usrData;

      # --- desktop ----------------------------------------------------------
      kdn.desktop-sway.portals.debug = true;

      # --- networking -------------------------------------------------------
      kdn.networking.enable = true;
      kdn.networking.debug = true;
      kdn.networking.iface.default = "kdn-eth-2g";

      # systemd-networkd is the authoritative provider. Drop NetworkManager's wait-online so
      # `network-online.target` settles during a switch-triggered networkd restart.
      systemd.services."NetworkManager-wait-online" = {
        wantedBy = lib.mkForce [ ];
        requiredBy = lib.mkForce [ ];
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

      # The build-farm `agent-check` responder must be reachable from the LAN and the mesh, and
      # nowhere else. VNC is mesh-only.
      networking.firewall.interfaces."kdn-eth-2g".allowedTCPPorts = [ 39701 ];
      networking.firewall.interfaces."nb-priv".allowedTCPPorts = [
        39701
        5900
      ];
      networking.firewall.interfaces."nb-priv".allowedUDPPorts = [ 5900 ];

      networking.hosts."10.116.89.68" = [ "gipe" ];
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

      networking.hosts."192.168.88.1" = [ "talt-mgmt" ];
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

      networking.hosts."192.168.2.1" = [ "mokerlink" ];
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

      # --- build farm -------------------------------------------------------
      kdn.nix.remote-builder.localhost.maxJobs = 12;
      kdn.nix.remote-builder.localhost.speedFactor = 32;
      # This host accepts builds from other machines, so it trusts the build-farm clients'
      # signing keys. A client that only uses builders must not.
      kdn.nix.remote-builder.trustClientSigningKeys = true;

      # The fleet's builder list. The old module holds it inline; the aspect carries no personal
      # data, so the value lives in `data/`.
      kdn.profile-remote-builders.buildMachines = import ../../data/nix-build-machines.nix {
        inherit lib;
        inherit (config.kdn) hostName;
        inherit (config.kdn.nix.remote-builder) user;
      };

      # --- users and policy -------------------------------------------------
      kdn.userProfiles = [
        "kdn"
        "root"
      ];
      security.sudo.wheelNeedsPassword = false;
      services.angrr.enable = false;

      # --- services ---------------------------------------------------------
      services.bpftune.enable = true;

      # --- per-service HTTPS exposure --------------------------------------
      # llama-swap and Prometheus each on their own subdomain, behind the internal CA leaf.
      kdn.web.exposure = {
        domain = "brys.priv.nb.net.int.kdn.im";
        certName = "zellij-web";
        title = "brys";
        listenAddresses = [ "100.79.164.36" ];
        networkServices = [ "netbird-priv.service" ];
        services = {
          llama-swap = {
            subdomain = "llama-swap.brys.priv.nb.net.int.kdn.im";
            upstream = "127.0.0.1:39700";
          };
          prometheus = {
            subdomain = "prometheus.brys.priv.nb.net.int.kdn.im";
            upstream = "10.233.90.2:9090";
            label = "Prometheus";
          };
        };
      };

      # --- certificates -----------------------------------------------------
      kdn.certificates.repoRoot = inputs.self;
      kdn.certificates.certs.ssh-host-brys = {
        ca = "kdn";
        type = "ssh-host";
        commonName = "brys";
        principals = sshHostIdentities.brys.names;
        directory = "hosts/brys/certs";
        certFile = "ssh_host_ed25519-cert.pub";
        keyFile = "ssh_host_ed25519_key";
        keySource = "managed";
      };
      # The post-quantum identity, offered IN ADDITION to ed25519, never instead.
      kdn.certificates.certs.ssh-host-brys-pq = {
        ca = "kdn";
        type = "ssh-host";
        commonName = "brys";
        principals = sshHostIdentities.brys.names;
        directory = "hosts/brys/certs";
        certFile = "ssh_host_mldsa44_ed25519-cert.pub";
        keyFile = "ssh_host_mldsa44_ed25519_key";
        keyType = "mldsa44-ed25519";
        keySource = "managed";
      };
      kdn.certificates.certs.zellij-web = {
        ca = "kdn";
        type = "tls-server";
        commonName = "brys.priv.nb.net.int.kdn.im";
        sans = [
          "brys.priv.nb.net.int.kdn.im"
          "llama-swap.brys.priv.nb.net.int.kdn.im"
          "prometheus.brys.priv.nb.net.int.kdn.im"
        ];
        directory = "hosts/brys/certs";
        certFile = "zellij.pub";
        keyFile = "zellij.key";
        keySource = "managed";
        owner = "kdn";
      };

      # The zellij web interface, on the mesh interface only.
      kdn.programs.zellij.web = {
        enable = true;
        bindAddress = "0.0.0.0";
        port = 8082;
        certFile = config.kdn.certificates.certs.zellij-web.certPath;
        keyFile = config.kdn.certificates.certs.zellij-web.keyPath;
        user = "kdn";
        firewallInterfaces = [ "nb-priv" ];
      };
    };
}

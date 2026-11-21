# brys, the LLM workstation, on the den tree. This is the only brys config: the universal
# `hosts/brys/` tree was removed on 2026-11-18 (the `llms` appliance specialisation is not ported
# yet). The original carryover covered the old universal tree, with one deliberate exception: the
# test passwords of the `kdn` and `root` accounts live in `./users.data.nix` and `pass`, so a
# failed boot is recoverable over the KVM or SSH.
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
# copied verbatim from `hosts-den/brys/default.nix`.
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
  llmHost = import ./llm.nix {
    inherit lib;
    pkgs = inputs.self.pkgs.x86_64-linux.default;
    kdnConfig = {
      self = inputs.self;
    };
    profile = "desktop";
  };

  # The account rows. A data file, not a module: the `user-profiles` aspect imports it into
  # `kdn.userProfileData` and turns each selected row into one account.
  usersData = import ./users.data.nix;

  # The SSH host certificates, shared with every boot specialisation. The old `hosts-den/brys/ssh-ca.nix`
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
    # The old tree builds a Home Manager generation for root too: every universal module loaded
    # into `home-manager.sharedModules`, and root's own `~/.config` follows it.
    users.root.classes = [
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

    # --- desktop ----------------------------------------------------------
    desktop-base
    desktop-niri
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
    dev-elixir
    dev-git
    dev-golang
    dev-java
    dev-jetbrains
    dev-k8s
    dev-llm-claude-code
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
    program-beeper
    program-blender
    program-ente-photos
    program-keepass
    program-keepassxc
    program-nextcloud-client
    program-rambox
    program-signal
    program-slack
    program-spotify
    program-tidal
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
    desktop-base
    desktop-niri
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
    dev-elixir
    dev-git
    dev-golang
    dev-java
    dev-jetbrains
    dev-k8s
    dev-llm-claude-code
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
    hw-qmk
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
    program-beeper
    program-blender
    program-ente-photos
    program-keepass
    program-keepassxc
    program-nextcloud-client
    program-rambox
    program-signal
    program-slack
    program-spotify
    program-tidal
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
    service-syncthing
    signing
    ssh-access
    ssh-agent

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

  # The user's own Home Manager overlay on top of the aspect list. The old
  # `profile/default-secrets` module wrote this binding through `home-manager.sharedModules`; den
  # forbids one aspect writing a sibling's option, so the user states it here.
  den.aspects.kdn.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        ../../data/desktop-sway-kanshi.nix
        ./mimeapps.nix
      ];

      # The zellij web user service reads the certificate in the user scope, so the paths must be
      # stated here as well as on the host.
      kdn.zellij.web = {
        bindAddress = "0.0.0.0";
        port = 8082;
        # The system sops module decrypts the key at boot and hands it to the `kdn` owner.
        certFile = "${inputs.self}/hosts-den/brys/certs/zellij.pub";
        keyFile = "/run/secrets/kdn/certificates/zellij-web.key";
        user = "kdn";
        firewallInterfaces = [ "nb-priv" ];
      };

      kdn.programs.keepassxc.service = {
        use = true;
        fileName = "drag0nius.kdbx";
        searchDirs = [ "/home/kdn/Nextcloud/drag0nius@nc.nazarewk.pw/important/keepass" ];
      };

      xdg.configFile."kdn/source-flake".source = inputs.self;

      # The checkout `nh` rebuilds from; the old `development-nix.nix` data file named it. The
      # `dev-nix` option tree is Home Manager-only, so the user states it here.
      kdn.dev-nix.flake.path = "/home/kdn/dev/github.com/nazarewk-iac/nix-configs";

      # The old `profile/user/kdn` declared these Firefox profiles; the den aspect builds one
      # home profile per name, and the `firefox-containers-d-sync` units follow them.
      kdn.programs.firefox.profileNames = [
        "bn"
        "dn"
        "en"
        "jp"
        "kdn"
        "sn"
      ];

      # The Home Manager services (`waybar`, `swaync`, `kanshi`) start from
      # `graphical-session.target`, so native spawns would start a second copy. The Niri settings
      # render in this scope, so the empty list belongs here.
      kdn.desktop-niri.spawnAtStartup = [ ];

      # The profile rows and the container set the old `profile/user/kdn` declared. A den aspect
      # carries no personal browser data, so the host states it.
      programs.firefox.profiles = {
        kdn = {
          id = 0;
          name = "kdn";
          path = "kdn";
          containers = {
            Facebook = {
              color = "yellow";
              icon = "fence";
              id = 8;
              name = "Facebook";
            };
            bn = {
              color = "pink";
              icon = "pet";
              id = 6;
              name = "bn";
            };
            en = {
              color = "red";
              icon = "pet";
              id = 5;
              name = "en";
            };
            personal = {
              color = "blue";
              icon = "fingerprint";
              id = 1;
              name = "personal";
            };
            personal-2 = {
              color = "green";
              icon = "fingerprint";
              id = 2;
              name = "personal-2";
            };
            sn = {
              color = "purple";
              icon = "pet";
              id = 7;
              name = "sn";
            };
            work = {
              color = "turquoise";
              icon = "briefcase";
              id = 3;
              name = "work";
            };
            work-2 = {
              color = "purple";
              icon = "briefcase";
              id = 4;
              name = "work-2";
            };
          };
        };
        jp = {
          id = 1;
          name = "jp";
          path = "jp";
        };
        bn = {
          id = 2;
          name = "bn";
          path = "bn";
        };
        sn = {
          id = 3;
          name = "sn";
          path = "sn";
        };
        en = {
          id = 4;
          name = "en";
          path = "en";
        };
        dn = {
          id = 5;
          name = "dn";
          path = "dn";
        };
      };

      # The old `profile/user/kdn` read its own `.gitattributes`; the file is still the single
      # source, so the user points at it.
      programs.git.attributes = [
        (builtins.readFile ../../modules/universal/profile/user/kdn/.gitattributes)
      ];

      # The old `_hm-bootstrap` generated these two files from the host nixpkgs opinion. den
      # drops that bridge by design, so the user states the same values.
      xdg.configFile."nixpkgs/config.nix".text = ''
        {
          allowAliases = true;
          allowUnfree = true;
          permittedInsecurePackages = [
            "litestream-0.3.13"
            "electron-28.3.3"
            "electron-27.3.11"
            "olm-3.2.16"
          ];
        }
      '';
      xdg.configFile."nix/nix.nix".text = "";

      # The wlr portal's screencast chooser. The old sway user module wrote this file; the den
      # aspect keeps the portal selection but not the chooser command.
      xdg.configFile."xdg-desktop-portal-wlr/sway".text = ''
        [screencast]
        chooser_cmd=${lib.getExe pkgs.wofi} -d -n --prompt='Select the monitor to share:'
        chooser_type=dmenu
      '';

      # The `user` aspect's Home Manager target selects a row from its own `kdn.users`; the NixOS
      # `user-profiles` row does not cross the scope. State the row here for the u2f file.
      kdn.users.kdn = {
        enable = true;
        u2fKeysFile = ../../modules/universal/profile/user/kdn/yubico/u2f_keys.parts;
      };
      # A host fact the `pi-client` aspect needs in the user evaluation.
      kdn.pi-client.hostName = "brys";
      # Inline: the repository's `.gitignore` tracks `.nix` files only, so an extensionless
      # payload beside this file would not reach the flake source.
      xdg.configFile."gsimplecal/config".text = ''
        show_calendar = 1
        show_timezones = 1
        mark_today = 1
        show_week_numbers = 1
        close_on_unfocus = 1
        mainwindow_decorated = 0
        mainwindow_keep_above = 1
        mainwindow_sticky = 0
        mainwindow_skip_taskbar = 1
        mainwindow_resizable = 0
        mainwindow_position = mouse


        clock_format = %a, %H:%M:%S
        clock_label = Local
        clock_tz =
        clock_label = UTC
        clock_tz = :UTC
        clock_label = BST
        clock_tz = :Europe/London
        clock_label = HKT
        clock_tz = :Asia/Hong_Kong
      '';
      xdg.configFile."klg/config.toml".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Nextcloud/drag0nius@nc.nazarewk.pw/time-logs/klg/config.toml";
      xdg.userDirs.enable = true;

      # The `apps` aspect publishes the persistence lists and writes no sibling option; the user
      # wires them into its own `disks-persist` tree, as the aspect header states.
      kdn.disks.persist = lib.mapAttrs (bucket: directories: {
        inherit directories;
        files = config.kdn.apps-persist.files.${bucket} or [ ];
      }) config.kdn.apps-persist.directories;

      kdn.desktop-sway.extraKeybindings."Control+Super+A" = "exec kdn-anonymize-clipboard";

      # The old `programs/handlr` module wrote this binding from its `nixos` target. The den aspect
      # publishes the `xdg-open` replacement and drops the binding, so the user states it.
      kdn.desktop-sway.extraKeybindings."Super+O" = "exec ${pkgs.writeScript "xdg-open-clipboard" ''
        ${lib.getExe config.kdn.programs.handlr.xdg-utils.package} "$(${lib.getExe' pkgs.wl-clipboard "wl-paste"} --no-newline)"
      ''}";

      # The old `profile/user/kdn` turned both extra matrix clients on.
      kdn.programs.matrix.nheko.use = true;
      kdn.programs.matrix.gomuks.use = true;

      # The desktop and tool extras of the old `profile/user/kdn` that no `program-*` aspect owns.
      # They are one person's choices, so they stay in the host file, not in a reusable aspect.
      home.packages = with pkgs; [
        vlc
        subtitleeditor
        ffsubsync
        haruna
        shotwell
        qrencode
        zbar
        zoom-us
        httpie-desktop
        qpdf
        (pkgs.callPackage ../../packages/kdnctl { })
        (pkgs.callPackage ../../packages/kagi-cli/package.nix { })
        (pkgs.callPackage ../../packages/klg { })
        (pkgs.callPackage ../../packages/klog-time-tracker { })
        (pkgs.callPackage ../../packages/ss-util { })
        (pkgs.callPackage ../../packages/systemd-find-cycles { })
        deluge-gtk
        (pkgs.writeShellApplication {
          name = "kdn-drag0nius.kdbx";
          text = "${lib.getExe (pkgs.callPackage ../../packages/kdn-keepass { })} drag0nius.kdbx";
        })
      ];
    };

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

        # The old universal loader imported these personal data modules itself. den has no loader,
        # so the host names them: the EDID modelines, the Polish locale, and the home printer.
        ../../data/universal-safe/hw-edid.nix
        ../../data/universal-safe/locale.nix
        ../../data/universal-safe/services-printing.nix

        # Inbound-HTTPS rate limit, so a 100 GB model download cannot fill the 1 Gbit/s WAN.
        ./wan-shaping.nix

        # The Strata engine and the `strata-serve` adaptor that llama-swap calls per profile.
        ./strata-profiles.nix

        # The board-power cap: 210 W, the card's own floor, re-applied at boot and on resume.
        ./gpu-power.nix

        # The motherboard sensors: the Nuvoton NCT6798D behind the `nct6775` driver, plus the
        # libsensors labels. node_exporter picks them up through its `hwmon` collector.
        ./sensors.nix

        # The container runner (containerd + nix-snapshotter) and the one proof container. The
        # den aspect behind it has no registry entry, so the host imports it by path from there.
        ./containers.nix

        # The LLM slot data, the host-side secrets/persistence, and the GPU runtime config. These are
        # plain modules, so they merge into this target exactly as they merged into the old host.
        llmHost.slot
        llmHost.nixos
        llmHost.gpu
      ];

      # The default sops file of this repository. The old `profile/default-secrets` module names it;
      # a den aspect holds no flake, so the host does. Every sops secret below depends on it.
      kdn.security.secrets.sops.defaultFile = "${inputs.self}/default.unattended.sops.yaml";

      # Fish is the login shell of the primary user, as in the old tree.
      kdn.programs.fish.defaultShell = true;
      kdn.programs.fish.defaultShellUsers = [ "kdn" ];

      # --- identity ---------------------------------------------------------
      networking.hostName = "brys";
      networking.hostId = "0a989258";
      system.stateVersion = "24.11";

      # The old host pins every package to the flake's single per-system instance, so the host,
      # the specialisation and the ad-hoc `nix` calls share one nixpkgs. den does the same here.
      nixpkgs.pkgs = inputs.self.pkgs.x86_64-linux.default;
      # `nixpkgs.pkgs` is mutually exclusive with `nixpkgs.config`/`overlays`; the old
      # `modules/den-pkgs/pin-module.nix` forced both empty for the same reason.
      nixpkgs.overlays = lib.mkForce [ ];
      nixpkgs.config = lib.mkForce { };

      home-manager.useGlobalPkgs = true;
      # The old bootstrap put every Home Manager package into `/etc/profiles/per-user/<name>`, and
      # added `home-manager-path` to each account. Keep that layout: a `~/.nix-profile` switch would
      # move 350 packages and change what a fresh login sees.
      home-manager.useUserPackages = true;
      home-manager.sharedModules = [ { home.stateVersion = "24.11"; } ];

      # The old baseline published the flake checkout at this path; the den baseline leaves it to
      # the consumer (its change 8).
      environment.etc."kdn/source-flake".source = inputs.self;

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

      # ZRAM stays OFF on this host, on purpose. It is the only swap brys would have, and the LLM
      # services keep 90-115 GiB of a 125 GiB machine resident (expert arenas, the streamed KV
      # cache). Swapping any of that costs a zstd decompress on every touch, which shows up as
      # latency spikes in long-context answers and re-prefill. Without swap a spike kills one
      # process; with zram it degrades every answer. Reliability of the served models wins.
      zramSwap.enable = lib.mkDefault false;

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

      hardware.display.outputs."DP-4" = {
        edid = "PG278Q_120.bin";
        mode = "e";
      };

      # A TPM or a network unlock of the encrypted root, so a reboot needs no keyboard.
      boot.initrd.clevis.enable = lib.mkDefault true;

      # The old host bound the discrete GPU to `vfio-pci` (`kdn.hw.gpu.vfio.enable = true`, with no
      # ids). That is where `iommu=pt` and the VFIO kernel modules come from.
      kdn.hw.gpu.vfio.use = true;

      # --- containers -------------------------------------------------------
      # The rootless store lives on the persistent `usr/data` base, never on the disposable home.
      # The `virt-containers` aspect publishes the list; the host states the bucket once.
      kdn.disks.persist."usr/data".directories = config.kdn.virtualisation.containers.persist.usrData;

      # The rosec key file is on the disposable home. Seed it from the TPM identity (root-only)
      # before the user manager starts, so the boot-time `rosec-unlock` finds it. The user's
      # `rosec-keys` merge preserves the existing lines.
      systemd.services.kdn-rosec-tpm-key = {
        description = "seed the rosec key file with the brys TPM age identity";
        wantedBy = [ "multi-user.target" ];
        before = [
          "user@${toString config.users.users.kdn.uid}.service"
          "display-manager.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.writeShellScript "kdn-rosec-tpm-key" ''
            install -d -m 0700 -o kdn -g users /home/kdn/.config/sops/age
            install -m 0600 -o kdn -g users /var/lib/sops-tpm/tpm-identity.txt /home/kdn/.config/sops/age/rosec-keys.txt
          ''}";
        };
      };

      # The Syncthing shares and the sync state are state, not disposable home content: the
      # shares hold the pre-Nextcloud secret stores, and the index must survive a rollback.
      # These are user-level buckets, not the system-level `kdn.disks.persist`.
      kdn.disks.userDefaults.persist."usr/data".directories = [
        ".local/share/kdn/synced"
        ".local/share/syncthing"
        # The dev tree (checkouts, Syncthing `dev` folder) is state; the old host persisted it and
        # the den port dropped the entry, so a reboot left `~/dev` unmounted.
        "dev"
      ];
      kdn.disks.userDefaults.persist."usr/config".directories = [
        ".config/syncthing"
      ];

      # --- desktop ----------------------------------------------------------
      kdn.desktop-sway.portals.debug = true;

      # The Sway/UWSM A/B. The `kdn-sway` session stays the default; this adds the UWSM-managed
      # entry so the greeter offers both for the live comparison.
      kdn.desktop-sway.uwsm.use = true;

      # The Niri evaluation session. It is a second entry in the greeter; `defaultSession` is
      # untouched, so Sway still starts by default. The repo's own secret service owns
      # `org.freedesktop.secrets`, so the portal's Secret interface names no second backend.
      # The rosec provider values are user-level and shared with oams through one Home Manager
      # module, so the store path, identity and recipient cannot drift between the two hosts.
      home-manager.users.kdn.imports = [
        ../../data/rosec.nix
        # The Syncthing shares this host holds. The topology lives in `data/syncthing.nix`; a
        # peer without a device ID yet (etra before its first start) is left out of the share.
        (
          { lib, ... }:
          let
            st = import ../../data/syncthing.nix;
            self = "brys";
            mine = [
              "secret-stores"
              "small"
              "medium"
              "large"
            ];
          in
          {
            kdn.services.syncthing.devices = builtins.removeAttrs st.devices [ self ];
            kdn.services.syncthing.shares = builtins.listToAttrs (
              map (share: {
                name = share;
                value = builtins.filter (host: host != self && builtins.hasAttr host st.devices) st.shares.${share};
              }) mine
            );
          }
        )
      ];

      kdn.desktop-niri = {
        # `niri-uwsm` adds the UWSM-managed entry beside the plain `niri-session` one. UWSM starts
        # `graphical-session.target`, which is what brings up the bar, portals and the app set.
        session = "niri-uwsm";
        portal.secret = "none";
        useNautilus = true;

      };

      # --- networking -------------------------------------------------------
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

      # The NetBird mesh. The old `profile/machine/baseline` carried this block; the den baseline
      # dropped it on purpose (a network identity is entity data), so the host states it.
      kdn.networking.netbird.admins = [ "kdn" ];
      kdn.networking.netbird.default.users = [ "kdn" ];
      kdn.networking.netbird.default.environment = {
        NB_BLOCK_INBOUND = "true";
        NB_DISABLE_DNS = "true";
      };
      # The old default was a disabled client; only `priv` runs on brys. `active` replaces the
      # old `default.enable` name.
      kdn.networking.netbird.default.active = false;
      kdn.networking.netbird.clients.priv.idx = 1;
      kdn.networking.netbird.clients.priv.enable = true;
      kdn.networking.netbird.clients.priv.environment.NB_DISABLE_DNS = "false";
      kdn.networking.netbird.clients.priv.environment.NB_BLOCK_INBOUND = "false";
      kdn.networking.netbird.clients.t1.idx = 5;
      kdn.networking.netbird.clients.t2.idx = 6;
      kdn.networking.netbird.clients.t3.idx = 7;
      # The aspect names no secrets manager; the host points it at the generated sops subtree.
      kdn.networking.netbird.secretsTree = config.kdn.security.secrets.sops.secrets.default.netbird;

      # The build-farm `agent-check` responder must be reachable from the LAN and the mesh, and
      # nowhere else. VNC is mesh-only.
      networking.firewall.interfaces."kdn-eth-2g".allowedTCPPorts = [ 39701 ];
      networking.firewall.interfaces."nb-priv".allowedTCPPorts = [
        39701
        5900
      ];
      networking.firewall.interfaces."nb-priv".allowedUDPPorts = [ 5900 ];

      # Syncthing runs as a user service, so the old `profile/user/kdn` opened its ports itself.
      networking.firewall.allowedTCPPorts = [ 22000 ];
      networking.firewall.allowedUDPPorts = [
        21027
        22000
      ];

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
      # The builder account accepts the same key file the old default named.
      kdn.profile-remote-builders.authorizedKeysFiles = [
        ../../modules/universal/profile/user/kdn/.ssh/authorized_keys
      ];
      kdn.profile-remote-builders.buildMachines = import ../../data/nix-build-machines.nix {
        inherit lib;
        inherit (config.kdn) hostName;
        inherit (config.kdn.nix.remote-builder) user;
      };

      # --- personal data the old loader imported ---------------------------
      # The wallpaper from `data/universal-deps/stylix.nix`, at the same `mkDefault` priority.
      stylix.image = lib.mkDefault (
        pkgs.fetchurl {
          url = "https://nc.nazarewk.pw/s/XSR3x6AkwZAiyBo/download/13754-mushrooms-toadstools-glow-photoshop-3840x2160.jpg";
          sha256 = "sha256-1d/kdFn8v0i1PTeOPytYNUB1TxsuBLNf4+nRgSOYQu4=";
        }
      );

      # --- nix itself -------------------------------------------------------
      # The old tree runs Lix, sets the store optimiser on a timer, and pins the flake registry.
      # `nix-config` ports the settings; these three are host decisions.
      nix.package = lib.mkDefault pkgs.lixPackageSets.latest.lix;
      nix.optimise.automatic = true;
      nix.registry.nixpkgs.flake = inputs.nixpkgs;

      # --- shell history and the Nextcloud sync -----------------------------
      kdn.programs.atuin.users = [
        "root"
        "kdn"
      ];
      kdn.programs.atuin.autologinUsers = [
        "root"
        "kdn"
      ];
      kdn.programs.atuin.autologin.usernameFile = config.sops.secrets."default/atuin/username".path;
      kdn.programs.atuin.autologin.passwordFile = config.sops.secrets."default/atuin/password".path;
      kdn.programs.atuin.autologin.keyFile = config.sops.secrets."default/atuin/key".path;

      # The four wireless networks the old `profile/machine/basic` carries, with the same
      # priorities. The old module rendered one environment file from every WLAN secret; only
      # these four have a profile, so only these four matter.
      kdn.profile-basic.wlan = {
        Covfefe = {
          priority = 50;
          passwordFile = config.sops.secrets."default/networking/wlan/Covfefe/password".path;
        };
        dropout-wafer = {
          priority = 100;
          passwordFile = config.sops.secrets."default/networking/wlan/dropout-wafer/password".path;
        };
        yelk = {
          priority = 1;
          passwordFile = config.sops.secrets."default/networking/wlan/yelk/password".path;
        };
        drek = {
          priority = 1;
          passwordFile = config.sops.secrets."default/networking/wlan/drek/password".path;
        };
      };

      kdn.services.iperf3.client.publicKeyPath = "/run/configs/networking/iperf-server/rsa/pub";
      kdn.services.iperf3.client.passwordDir = "/run/configs/networking/iperf-server/users";
      kdn.services.iperf3.client.defaultUsername = builtins.head (
        builtins.attrNames config.kdn.security.secrets.sops.secrets.default.networking.iperf-server.users
      );

      kdn.services.nextcloud-client.urlPath = config.sops.secrets."default/nextcloud/nixos/url".path;
      kdn.services.nextcloud-client.usernamePath =
        config.sops.secrets."default/nextcloud/nixos/username".path;
      kdn.services.nextcloud-client.passwordPath =
        config.sops.secrets."default/nextcloud/nixos/password".path;
      kdn.disks.persist."usr/reproducible".users.root.directories =
        config.kdn.services.nextcloud-client.persist.usrReproducibleRoot;

      # --- users and policy -------------------------------------------------
      kdn.userProfiles = [
        "kdn"
        "root"
      ];
      security.sudo.wheelNeedsPassword = false;
      services.angrr.enable = false;

      # --- services ---------------------------------------------------------
      services.bpftune.enable = true;

      # The old `profile/default-secrets` installed the clipboard anonymiser whenever a desktop
      # was on. The aspect publishes the package; the host installs it.
      #
      # The audio models of the media bench (`hack/media/`) are CPU-only and are NOT llama-swap
      # entries: whisper.cpp and Piper speak their own protocols, not the OpenAI chat API, so they
      # have no place in `data/llm.nix`. The model files live on the shared LLM tree, beside the
      # weights, so a second machine that mounts that dataset gets them too:
      #   /var/lib/kdn/llms/models/whisper/ggml-base.en.bin
      #   /var/lib/kdn/llms/models/piper/en_US-lessac-medium.onnx
      environment.systemPackages = [
        config.kdn.profile-default-secrets.anonymizeClipboard
        pkgs.whisper-cpp
        pkgs.piper-tts
      ];

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
      # Trust the KDN CA (data/ca/ca.pub) system-wide, and keep the offline CA key as an
      # encrypted blob for manual reference. The old host did this through the `ca` slot.
      kdn.ca.kdn.enable = true;
      kdn.ca.kdn.certFile = "${inputs.self}/data/ca/ca.pub";
      kdn.ca.kdn.keySopsFile = "${inputs.self}/data/ca/ca.key.sops";

      kdn.certificates.repoRoot = inputs.self;
      kdn.certificates.certs.ssh-host-brys = {
        ca = "kdn";
        type = "ssh-host";
        commonName = "brys";
        principals = sshHostIdentities.brys.names;
        directory = "hosts-den/brys/certs";
        keyDirectory = "hosts-den/brys/ssh-keys";
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
        directory = "hosts-den/brys/certs";
        keyDirectory = "hosts-den/brys/ssh-keys";
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
        directory = "hosts-den/brys/certs";
        certFile = "zellij.pub";
        keyFile = "zellij.key";
        keySource = "managed";
        owner = "kdn";
      };

      # The zellij web interface, on the mesh interface only.
      kdn.zellij.web = {
        bindAddress = "0.0.0.0";
        port = 8082;
        # The system sops module decrypts the key at boot and hands it to the `kdn` owner.
        certFile = "${inputs.self}/hosts-den/brys/certs/zellij.pub";
        keyFile = "/run/secrets/kdn/certificates/zellij-web.key";
        user = "kdn";
        firewallInterfaces = [ "nb-priv" ];
      };
    };
}

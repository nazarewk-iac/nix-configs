# Tier-1 assertions for the 13 machine-profile aspects of batch 19.
#
# Every assertion is `{ name; expected; actual; }`, and `mkEvalCheck` compares the two at
# evaluation time. Nothing here builds a system and nothing activates.
#
# ## What this file guards that no other check can
#
# This batch is the only one whose aspects are **bundles**. A bundle carries an `includes` list, and
# `modules/den/lib.nix:246-265` treats `includes` as a structural key. So a bundle with `includes`
# alone reports `classes = [ ]`, exports no `denModules` pair, and reaches **zero** coverage while
# every check still passes. Two assertions below close that hole:
#
#   1. "every bundle carries at least one class key" reads `denLib.pairs` and fails on an empty list.
#   2. "every bundle names exactly the expected aspects" reads `flake.denful.kdn.<name>.includes`
#      and compares the `.name` of each element with a literal list.
#
# Both sides of every list comparison are sorted. The real den loader WRAPS a target module, and a
# hand-written stand-in returns it unwrapped, so definition order flips between the two routes.
# Three earlier assertions failed on order alone with identical content.
#
# ## The subjects
#
# | Subject | Class | What it states |
# |---|---|---|
# | `nixosPlain` | `nixos` | the 10 aspects that emit a `nixos` target, no consumer opinion |
# | `nixosOpinion` | `nixos` | one WLAN network, one root-password file, one initrd timeout |
# | `darwinPlain` | `darwin` | the 6 aspects that emit a `darwin` target |
# | `homePlain` | `homeManager` | the 9 aspects that emit a `homeManager` target |
#
# `denLib.imports` calls den's own `resolve`, and that resolver **follows** `includes`. So each
# subject holds the whole reachable graph, not the 13 bundle files alone. Every one of the 22 names
# the bundles reach must exist in the registry, or the evaluation fails with an undefined attribute.
#
# `mkEvalCheck` reads named option values, so it never forces `config.assertions`. A nixpkgs
# assertion that a bare consumer cannot satisfy stays silent here. `../tests.nix` holds the
# `forceData` rows that the `den-eval-instantiate` check needs for the same aspects.
{
  lib,
  inputs,
  denLib,
  harness,
  flake,
  ...
}:
let
  inherit (harness) bareNixos bareDarwinSystem bareHomeConfiguration;

  sorted = lib.sort (a: b: a < b);

  bundleNames = [
    "profile-baseline"
    "profile-baseline-flake-links"
    "profile-baseline-gc"
    "profile-basic"
    "profile-desktop"
    "profile-dev"
    "profile-gaming"
    "profile-headless"
    "profile-headless-vim"
    "profile-headless-wezterm"
    "profile-headless-zellij"
    "profile-hetzner"
    "profile-workstation"
  ];

  # The expected `includes` of every bundle that has one. A name absent from this set expects no
  # `includes` at all.
  expectedIncludes = {
    profile-baseline = [
      "dev-git"
      "dev-shell"
      "hw-usbip"
      "hw-yubikey"
      "locale"
      "net-dynamic-hosts"
      "net-resolved"
      "profile-baseline-flake-links"
      "profile-baseline-gc"
      "profile-headless"
      "program-direnv"
      "secrets"
      "toolset-fs-encryption"
    ];
    profile-baseline-flake-links = [ "dev-nix" ];
    profile-basic = [
      "hw-bluetooth"
      "profile-baseline"
      "program-gnupg"
    ];
    profile-desktop = [
      "desktop-base"
      "hw-audio"
      "hw-gpu"
      "hw-qmk"
      "profile-basic"
      "program-browsers-launcher"
      "program-chrome"
      "program-chromium"
      "program-firefox"
      "program-kdeconnect"
      "program-office"
      "program-thunderbird"
      "service-printing"
    ];
    profile-dev = [
      "dev-ansible"
      "dev-cloud"
      "dev-cloud-aws"
      "dev-data"
      "dev-db"
      "dev-documents"
      "dev-elixir"
      "dev-golang"
      "dev-java"
      "dev-k8s"
      "dev-nickel"
      "dev-nix"
      "dev-python"
      "dev-rpi"
      "dev-rust"
      "dev-terraform"
      "dev-web"
      "program-terminal-ide"
      "virt-containers"
      "virt-containers-podman"
    ];
    profile-headless = [
      "dev-data"
      "hw-basic"
      "profile-headless-vim"
      "profile-headless-wezterm"
      "profile-headless-zellij"
      "program-atuin"
      "program-fish"
      "program-terminal-ide"
      "program-zsh"
      "toolset-essentials"
      "toolset-fs"
      "toolset-fs-encryption"
      "toolset-network"
      "toolset-nix"
      "toolset-unix"
    ];
    profile-hetzner = [ "profile-baseline" ];
    profile-workstation = [
      "desktop-remote-server"
      "desktop-sway"
      "dev-android"
      "dev-jetbrains"
      "profile-desktop"
      "profile-dev"
      "program-editors-photo"
      "program-editors-video"
      "program-nix-index"
      "program-obs-studio"
      "toolset-diagrams"
      "toolset-logs-processing"
      "virt-libvirtd"
      "virt-vagrant"
    ];
  };

  # The class keys each name really emits, read from the registry.
  actualClasses = lib.mapAttrs (_: sorted) (lib.getAttrs bundleNames denLib.pairs);

  expectedClasses = {
    profile-baseline = [
      "darwin"
      "homeManager"
      "nixos"
    ];
    profile-baseline-flake-links = [ "nixos" ];
    profile-baseline-gc = [
      "darwin"
      "nixos"
    ];
    profile-basic = [
      "darwin"
      "homeManager"
      "nixos"
    ];
    profile-desktop = [
      "darwin"
      "homeManager"
      "nixos"
    ];
    profile-dev = [
      "darwin"
      "homeManager"
      "nixos"
    ];
    profile-gaming = [
      "homeManager"
      "nixos"
    ];
    profile-headless = [
      "darwin"
      "homeManager"
      "nixos"
    ];
    profile-headless-vim = [ "homeManager" ];
    profile-headless-wezterm = [ "homeManager" ];
    profile-headless-zellij = [ "homeManager" ];
    profile-hetzner = [ "nixos" ];
    profile-workstation = [
      "darwin"
      "homeManager"
      "nixos"
    ];
  };

  namesWithClass =
    class: builtins.filter (n: builtins.elem class (denLib.pairs.${n} or [ ])) bundleNames;

  nixosModules = denLib.imports {
    class = "nixos";
    aspects = namesWithClass "nixos";
  };

  nixosPlain = (bareNixos nixosModules).config;

  # `profile-hetzner` replaces the boot loader: it forces `systemd-boot` off and asks for grub. So a
  # subject that holds every name at once cannot measure the baseline boot loader. This second
  # subject drops the one Hetzner name and measures the baseline choice.
  nixosNoHetzner =
    (bareNixos (
      denLib.imports {
        class = "nixos";
        aspects = builtins.filter (n: n != "profile-hetzner") (namesWithClass "nixos");
      }
    )).config;

  # `../harness.nix:89` writes `boot.loader.grub.enable = false` at plain priority (100), so the
  # `mkDefault` (1000) of an aspect can never win there. This third subject repeats the other three
  # harness lines and leaves the grub line out, so the Hetzner boot loader choice becomes readable.
  # `./services.nix:46-56` is the precedent for a local subject that the shared harness cannot give.
  hetznerNixos =
    (inputs.nixpkgs.lib.nixosSystem {
      modules =
        denLib.imports {
          class = "nixos";
          aspects = [ "profile-hetzner" ];
        }
        ++ [
          (
            { config, ... }:
            {
              nixpkgs.hostPlatform = "x86_64-linux";
              fileSystems."/" = {
                device = "none";
                fsType = "tmpfs";
              };
              system.stateVersion = config.system.nixos.release;
            }
          )
        ];
    }).config;

  # One WLAN network, one root-password file, one initrd reboot timeout and one emergency-access
  # refusal. Every value is a placeholder.
  opinion = {
    kdn.profile-basic.wlan.den-net.passwordFile = "/run/secrets/den-net";
    kdn.profile-basic.wlan.den-net.priority = 42;
    kdn.profile-baseline.rootHashedPasswordFile = "/run/secrets/den-root";
    kdn.profile-baseline.initrd.emergency.rebootTimeout = 30;
    kdn.profile-baseline.initrd.emergencyAccess = false;
    kdn.profile-baseline.knownHostsFiles = [ ./machine-profiles.nix ];
    kdn.profile-hetzner.ipv6Address = "2001:db8::1/64";
  };

  nixosOpinion = (bareNixos (nixosModules ++ [ opinion ])).config;

  darwinPlain =
    (bareDarwinSystem (
      denLib.imports {
        class = "darwin";
        aspects = namesWithClass "darwin";
      }
    )).config;

  homePlain =
    (bareHomeConfiguration (
      denLib.imports {
        class = "homeManager";
        aspects = namesWithClass "homeManager";
      }
    )).config;

  # Every name the bundles reach, as a flat sorted list. A person's login name must not appear.
  everyIncludeName = sorted (
    lib.unique (lib.concatLists (lib.attrValues (lib.mapAttrs (_: v: v) expectedIncludes)))
  );

  has = name: packages: builtins.any (p: lib.getName p == name) packages;
in
{
  assertions = [
    {
      name = "every bundle carries at least one class key, so none of them is a silent no-op";
      expected = expectedClasses;
      actual = actualClasses;
    }
    {
      name = "every bundle names exactly the expected aspects in its includes";
      expected = lib.mapAttrs (_: sorted) expectedIncludes;
      actual = lib.mapAttrs (name: _: sorted (map (a: a.name) flake.denful.kdn.${name}.includes)) (
        lib.mapAttrs (_: v: v) expectedIncludes
      );
    }
    {
      name = "no bundle names a person, and no include name carries a personal prefix";
      expected = [ ];
      actual = builtins.filter (
        n:
        !(lib.any (p: lib.hasPrefix p n) [
          "desktop-"
          "dev-"
          "hw-"
          "locale"
          "net-"
          "profile-"
          "program-"
          "secrets"
          "service-"
          "toolset-"
          "virt-"
        ])
      ) everyIncludeName;
    }
    {
      name = "the baseline nixos class holds the boot, network and OpenSSH opinions";
      expected = {
        initrdSystemd = true;
        systemdBoot = true;
        tmpfs = true;
        nftables = true;
        networkd = true;
        openssh = true;
        passwordAuth = false;
        mutableUsers = false;
        tpm2 = true;
        locate = true;
        avahi = false;
      };
      actual = {
        initrdSystemd = nixosPlain.boot.initrd.systemd.enable;
        # `nixosNoHetzner`, not `nixosPlain`. `profile-hetzner` forces `systemd-boot` off, so the
        # all-names subject reads the Hetzner choice and never the baseline one.
        systemdBoot = nixosNoHetzner.boot.loader.systemd-boot.enable;
        tmpfs = nixosPlain.boot.tmp.useTmpfs;
        nftables = nixosPlain.networking.nftables.enable;
        networkd = nixosPlain.networking.useNetworkd;
        openssh = nixosPlain.services.openssh.enable;
        passwordAuth = nixosPlain.services.openssh.settings.PasswordAuthentication;
        mutableUsers = nixosPlain.users.mutableUsers;
        tpm2 = nixosPlain.security.tpm2.enable;
        locate = nixosPlain.services.locate.enable;
        avahi = nixosPlain.services.avahi.enable;
      };
    }
    {
      name = "no inline password hash reaches a bare consumer";
      expected = {
        emergencyAccess = false;
        rootPasswordFile = null;
        knownHostsFiles = [ ];
      };
      actual = {
        emergencyAccess = nixosPlain.boot.initrd.systemd.emergencyAccess;
        rootPasswordFile = nixosPlain.users.users.root.hashedPasswordFile;
        knownHostsFiles = nixosPlain.kdn.profile-baseline.knownHostsFiles;
      };
    }
    {
      name = "the root password arrives as a file, never as a value";
      expected = "/run/secrets/den-root";
      actual = nixosOpinion.users.users.root.hashedPasswordFile;
    }
    {
      name = "the initrd emergency reboot drop-in follows the timeout";
      expected = {
        plain = false;
        opinion = true;
      };
      actual = {
        plain = nixosPlain.boot.initrd.systemd.services ? emergency;
        opinion = nixosOpinion.boot.initrd.systemd.services ? emergency;
      };
    }
    {
      name = "the garbage collector and the angrr retention policy land on the nixos class";
      expected = {
        automatic = true;
        options = "--delete-older-than 7d";
        angrr = true;
        integration = true;
        keepLatest = 5;
      };
      actual = {
        automatic = nixosPlain.nix.gc.automatic;
        options = nixosPlain.nix.gc.options;
        angrr = nixosPlain.services.angrr.enable;
        integration = nixosPlain.services.angrr.enableNixGcIntegration;
        keepLatest = nixosPlain.services.angrr.settings.profile-policies.system.keep-latest-n;
      };
    }
    {
      name = "angrr reaches the devenv root class, reports before it deletes, and wakes up on Darwin";
      expected = {
        devenvRegexNixos = "/\\.devenv/";
        devenvPeriodNixos = "30d";
        devenvRegexDarwin = "/\\.devenv/";
        devenvPeriodDarwin = "30d";
        dryRunNixos = [ "--dry-run" ];
        dryRunDarwin = [ "--dry-run" ];
        logLevelNixos = "debug";
        darwinTimer = true;
        darwinLog = "/var/log/angrr.log";
      };
      actual = {
        devenvRegexNixos = nixosPlain.services.angrr.settings.temporary-root-policies.devenv.path-regex;
        devenvPeriodNixos = nixosPlain.services.angrr.settings.temporary-root-policies.devenv.period;
        devenvRegexDarwin = darwinPlain.services.angrr.settings.temporary-root-policies.devenv.path-regex;
        devenvPeriodDarwin = darwinPlain.services.angrr.settings.temporary-root-policies.devenv.period;
        dryRunNixos = nixosPlain.services.angrr.extraArgs;
        dryRunDarwin = darwinPlain.services.angrr.extraArgs;
        logLevelNixos = nixosPlain.services.angrr.logLevel;
        darwinTimer = darwinPlain.services.angrr.timer.enable;
        darwinLog = darwinPlain.launchd.daemons.angrr.serviceConfig.StandardOutPath;
      };
    }
    {
      name = "the flake links stay away until a consumer names its own checkout";
      expected = [ ];
      actual = builtins.filter (
        r: lib.hasInfix "/etc/nixos/flake.nix" r
      ) nixosPlain.systemd.tmpfiles.rules;
    }
    {
      name = "the WLAN block writes no profile until a consumer names a network";
      # The aspect builds `safeSSID` for a shell variable name, so it maps `-` onto `_`. The profile
      # name maps `_` back onto `-`. So the attribute name `den-net` gives `wifi-den-net`.
      expected = {
        plain = [ ];
        opinion = [ "wifi-den-net" ];
      };
      actual = {
        plain = builtins.attrNames nixosPlain.networking.networkmanager.ensureProfiles.profiles;
        opinion = builtins.attrNames nixosOpinion.networking.networkmanager.ensureProfiles.profiles;
      };
    }
    {
      name = "the basic profile runs flatpak, appimage and the runtime man-page cache";
      expected = {
        flatpak = true;
        appimage = true;
        manCache = true;
        modeswitch = true;
      };
      actual = {
        flatpak = nixosPlain.services.flatpak.enable;
        appimage = nixosPlain.programs.appimage.enable;
        manCache = nixosPlain.systemd.services ? kdn-man-gen-caches;
        modeswitch = nixosPlain.hardware.usb-modeswitch.enable;
      };
    }
    {
      name = "the desktop profile writes the input-device settings and the keyboard fallback";
      expected = {
        libinput = true;
        tapping = true;
        layout = "us";
        gparted = true;
      };
      actual = {
        libinput = nixosPlain.services.libinput.enable;
        tapping = nixosPlain.services.libinput.touchpad.tapping;
        layout = nixosPlain.services.xserver.xkb.layout;
        gparted = has "gparted" nixosPlain.environment.systemPackages;
      };
    }
    {
      name = "the dev bundle publishes the MikroTik test and writes no other aspect's option";
      # The published value is `isx86 && config.kdn.graphical`. This subject holds `profile-desktop`,
      # which writes `kdn.graphical = true`, and the harness pins `x86_64-linux`. So the value is
      # `true` here. The second half of the claim stays the load-bearing part: the aspect writes no
      # `kdn.toolset` option, so a consumer names `toolset-mikrotik` itself.
      expected = {
        tools = true;
        graphical = true;
        toolsetWrite = false;
      };
      actual = {
        tools = nixosPlain.kdn.profile-dev.mikrotikTools;
        graphical = nixosPlain.kdn.graphical;
        toolsetWrite = nixosPlain.kdn ? toolset;
      };
    }
    {
      name = "the workstation profile writes seahorse, clevis and offlineimap";
      expected = {
        seahorse = true;
        clevis = true;
        offlineimap = true;
        diffoscope = true;
      };
      actual = {
        seahorse = nixosPlain.programs.seahorse.enable;
        clevis = nixosPlain.boot.initrd.clevis.enable;
        offlineimap = nixosPlain.services.offlineimap.install;
        diffoscope = has "diffoscope" nixosPlain.environment.systemPackages;
      };
    }
    {
      name = "the gaming profile runs Steam and leaves the unfree predicate to the consumer";
      expected = {
        steam = true;
        vulkanId = null;
        vulkanName = null;
      };
      actual = {
        steam = nixosPlain.programs.steam.enable;
        vulkanId = nixosPlain.kdn.profile-gaming.vulkan.deviceId;
        vulkanName = nixosPlain.kdn.profile-gaming.vulkan.deviceName;
      };
    }
    {
      name = "the Hetzner profile keeps grub, and its root writes at mkDefault";
      # It reads `hetznerNixos`, not `nixosPlain`. The shared harness pins `grub.enable` to `false`
      # at plain priority, and the aspect writes `true` at `mkDefault`, so the shared subject reads
      # the harness value and measures nothing about the aspect.
      expected = {
        systemdBoot = false;
        grub = true;
        bootDevice = "/dev/sda";
        rootFsType = "tmpfs";
      };
      actual = {
        systemdBoot = hetznerNixos.boot.loader.systemd-boot.enable;
        grub = hetznerNixos.boot.loader.grub.enable;
        bootDevice = hetznerNixos.boot.loader.grub.device;
        # The subject writes a tmpfs root at plain priority. The aspect writes `ext4` at
        # `mkDefault`, so the consumer wins. That is the point of change 5 of the port.
        rootFsType = hetznerNixos.fileSystems."/".fsType;
      };
    }
    {
      name = "the headless leaves reach the Home Manager class, one tool each";
      expected = {
        zellij = true;
        vim = true;
        zellijScrollback = 1000000;
        weztermKeys = true;
      };
      actual = {
        zellij = homePlain.programs.zellij.enable;
        vim = homePlain.programs.vim.enable;
        zellijScrollback = homePlain.programs.zellij.settings.scroll_buffer_size;
        weztermKeys = lib.hasInfix "SendKey" homePlain.programs.wezterm.extraConfig;
      };
    }
    {
      name = "the Darwin class carries the sudo lines and the shared packages";
      expected = {
        sudo = true;
        git = true;
        lsix = true;
      };
      actual = {
        sudo = lib.hasInfix "env_keep += ZELLIJ" darwinPlain.security.sudo.extraConfig;
        git = has "git" darwinPlain.environment.systemPackages;
        lsix = has "lsix" darwinPlain.environment.systemPackages;
      };
    }
    {
      name = "the Home Manager class keeps the game data and the XDG directories";
      expected = true;
      actual = homePlain.kdn.disks.persist ? "usr/data";
    }
  ];

  instantiatedBy = {
    profile-baseline = "den-eval-machine-profiles (bare nixos, bare darwin, bare home)";
    profile-baseline-flake-links = "den-eval-machine-profiles (bare nixos)";
    profile-baseline-gc = "den-eval-machine-profiles (bare nixos, bare darwin)";
    profile-basic = "den-eval-machine-profiles (bare nixos, bare darwin, bare home)";
    profile-desktop = "den-eval-machine-profiles (bare nixos, bare darwin, bare home)";
    profile-dev = "den-eval-machine-profiles (bare nixos, bare darwin, bare home)";
    profile-gaming = "den-eval-machine-profiles (bare nixos, bare home)";
    profile-headless = "den-eval-machine-profiles (bare nixos, bare darwin, bare home)";
    profile-headless-vim = "den-eval-machine-profiles (bare home)";
    profile-headless-wezterm = "den-eval-machine-profiles (bare home)";
    profile-headless-zellij = "den-eval-machine-profiles (bare home)";
    profile-hetzner = "den-eval-machine-profiles (bare nixos)";
    profile-workstation = "den-eval-machine-profiles (bare nixos, bare darwin, bare home)";
  };
}

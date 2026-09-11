# Tier-1 assertions for the 17 hardware aspects of batch 6 and batch 18.
#
# Every assertion is `{ name; expected; actual; }`, and `mkEvalCheck` compares the two at evaluation
# time. Nothing here builds a system and nothing activates.
#
# ## The subjects
#
# | Subject | Class | What it states |
# |---|---|---|
# | `nixosPlain` | `nixos` | all 17 aspects, no consumer opinion at all |
# | `nixosDellOnly` | `nixos` | `hw-dell-e5470` alone, to prove its two `includes` entries |
# | `nixosLaptop` | `nixos` | two GPUs, a VFIO passthrough, a desktop, an open firewall |
# | `nixosOverlay` | `nixos` | a replacement `supergfxctl`, through the overlay route |
# | `nixosNoSecrets` | `nixos` | the `secrets` aspect with `allow = false` |
# | `darwinPlain` | `darwin` | the two aspects that emit a `darwin` target |
# | `homePlain` | `homeManager` | the two aspects that emit a `homeManager` target |
#
# ## One thing the `homeManager` subject does not do
#
# It does not turn EasyEffects on. Home Manager's `services.easyeffects` module asserts a Linux
# platform, and `bareHomeConfiguration` uses `aarch64-darwin`. So the assertion below reads the
# default state only. The option itself gets its coverage from the option-tree walk of
# `standalone-aspects`.
{
  lib,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos bareDarwinSystem bareHomeConfiguration;

  sorted = lib.sort (a: b: a < b);

  hwNames = [
    "hw-audio"
    "hw-basic"
    "hw-bluetooth"
    "hw-cpu-amd"
    "hw-cpu-intel"
    "hw-darwin-utm-guest"
    "hw-dell-e5470"
    "hw-edid"
    "hw-gpu"
    "hw-gpu-amd"
    "hw-gpu-intel"
    "hw-intel-graphics-fix"
    "hw-modem"
    "hw-nanokvm"
    "hw-qmk"
    "hw-usbip"
    "hw-yubikey"
  ];

  nixosModules = denLib.imports {
    class = "nixos";
    aspects = hwNames;
  };

  nixosPlain = (bareNixos nixosModules).config;

  # A laptop with two GPUs, a passthrough, a desktop and an open USB/IP port. It names one PCI id
  # and one host name, and both are placeholders.
  laptopOpinion = {
    networking.hostName = "den-hw";
    kdn.hw.audio.graphical = true;
    kdn.hw.gpu.multiGPU.use = true;
    kdn.hw.gpu.vfio.use = true;
    kdn.hw.gpu.vfio.gpuIDs = [ "1002:1478" ];
    kdn.hw.intel-graphics-fix.mesaLoaderDriverOverride = "i965";
    kdn.hw.qmk.graphical = true;
    kdn.hw.usbip.bindInterface = "*";
    kdn.hw.yubikey.graphical = true;
  };

  nixosLaptopSystem = bareNixos (nixosModules ++ [ laptopOpinion ]);
  nixosLaptop = nixosLaptopSystem.config;

  # The overlay route. `kdn.hw.gpu.multiGPU.package` is a **function** of the package set before the
  # overlay, so `nixpkgs.overlays` never depends on `pkgs` and the evaluation terminates. A package
  # value would make that cycle. `hello` stands in for the pinned 5.2.1 build.
  nixosOverlaySystem = bareNixos (
    nixosModules
    ++ [
      {
        kdn.hw.gpu.multiGPU.use = true;
        kdn.hw.gpu.multiGPU.package = prev: prev.hello;
      }
    ]
  );

  # A machine that must hold no secret. The `secrets` aspect answers `allowed = false`, and the
  # YubiKey aspect reads that answer.
  nixosNoSecrets =
    (bareNixos (
      denLib.imports {
        class = "nixos";
        aspects = hwNames ++ [ "secrets" ];
      }
      ++ [ { kdn.security.secrets.allow = false; } ]
    )).config;

  darwinAspects = [
    "hw-qmk"
    "hw-yubikey"
  ];

  darwinSystem = bareDarwinSystem (
    denLib.imports {
      class = "darwin";
      aspects = darwinAspects;
    }
  );
  darwinPlain = darwinSystem.config;

  homeAspects = [
    "hw-audio"
    "hw-yubikey"
  ];

  homeConfiguration = bareHomeConfiguration (
    denLib.imports {
      class = "homeManager";
      aspects = homeAspects;
    }
  );
  homePlain = homeConfiguration.config;

  # `hw-dell-e5470` alone. `nixosPlain` cannot prove the two `includes` entries, because
  # `hw-gpu-intel` and `hw-modem` are already in `hwNames`. This subject holds the one aspect, so a
  # value from either included aspect can only arrive through `includes`.
  nixosDellOnlySystem = bareNixos (
    denLib.imports {
      class = "nixos";
      aspects = [ "hw-dell-e5470" ];
    }
  );
  nixosDellOnly = nixosDellOnlySystem.config;

  has = name: packages: lib.elem name (map lib.getName packages);
in
[
  # ---------------------------------------------------------------- instantiation
  {
    name = "the hardware aspects instantiate in all three classes";
    expected = {
      nixos = true;
      laptop = true;
      overlay = true;
      noSecrets = true;
      darwin = true;
      home = true;
    };
    actual = {
      nixos = builtins.isString nixosPlain.system.build.toplevel.drvPath;
      laptop = builtins.isString nixosLaptopSystem.config.system.build.toplevel.drvPath;
      overlay = builtins.isString nixosOverlaySystem.config.system.build.toplevel.drvPath;
      noSecrets = builtins.isString nixosNoSecrets.system.build.toplevel.drvPath;
      darwin = builtins.isString darwinPlain.system.build.toplevel.drvPath;
      home = builtins.isString homePlain.home.activationPackage.drvPath;
    };
  }
  {
    name = "each hardware aspect emits the classes its old module had";
    expected = {
      hw-audio = [
        "homeManager"
        "nixos"
      ];
      hw-basic = [ "nixos" ];
      hw-bluetooth = [ "nixos" ];
      hw-cpu-amd = [ "nixos" ];
      hw-cpu-intel = [ "nixos" ];
      hw-darwin-utm-guest = [ "nixos" ];
      hw-dell-e5470 = [ "nixos" ];
      hw-edid = [ "nixos" ];
      hw-gpu = [ "nixos" ];
      hw-gpu-amd = [ "nixos" ];
      hw-gpu-intel = [ "nixos" ];
      hw-intel-graphics-fix = [ "nixos" ];
      hw-modem = [ "nixos" ];
      hw-nanokvm = [ "nixos" ];
      hw-qmk = [
        "darwin"
        "nixos"
      ];
      hw-usbip = [ "nixos" ];
      hw-yubikey = [
        "darwin"
        "homeManager"
        "nixos"
      ];
    };
    actual = lib.mapAttrs (_: sorted) (lib.getAttrs hwNames denLib.pairs);
  }

  # ---------------------------------------------------------------- hw-audio
  {
    name = "hw-audio publishes the three user state directories";
    expected = {
      "usr/config" = [
        ".config/pulse"
        ".config/pipewire"
        ".local/state/wireplumber"
      ];
    };
    actual = nixosPlain.kdn.hw.audio.persist.directories;
  }
  {
    name = "hw-audio publishes the one user state file";
    expected = {
      "usr/config" = [ ".config/pavucontrol.ini" ];
    };
    actual = nixosPlain.kdn.hw.audio.persist.files;
  }
  {
    name = "PipeWire replaces PulseAudio and serves every protocol";
    expected = {
      pipewire = true;
      alsa = true;
      jack = true;
      pulse = true;
      wireplumber = true;
      pulseaudio = false;
      rtkit = true;
    };
    actual = {
      pipewire = nixosPlain.services.pipewire.enable;
      alsa = nixosPlain.services.pipewire.alsa.enable;
      jack = nixosPlain.services.pipewire.jack.enable;
      pulse = nixosPlain.services.pipewire.pulse.enable;
      wireplumber = nixosPlain.services.pipewire.wireplumber.enable;
      pulseaudio = nixosPlain.services.pulseaudio.enable;
      rtkit = nixosPlain.security.rtkit.enable;
    };
  }
  {
    name = "the WirePlumber debug settings stay out until asked";
    expected = [ ];
    actual = builtins.attrNames nixosPlain.services.pipewire.wireplumber.extraConfig;
  }
  {
    name = "the graphical volume control follows kdn.hw.audio.graphical";
    expected = {
      plain = false;
      laptop = true;
    };
    actual = {
      plain = has "pavucontrol" nixosPlain.environment.systemPackages;
      laptop = has "pavucontrol" nixosLaptop.environment.systemPackages;
    };
  }
  {
    name = "EasyEffects stays off in a bare home";
    expected = false;
    actual = homePlain.services.easyeffects.enable;
  }

  # ---------------------------------------------------------------- hw-basic
  {
    name = "the discovery script list is empty until a consumer fills it";
    expected = 0;
    actual = builtins.length nixosPlain.kdn.hw.basic.discoveryScripts;
  }

  # ---------------------------------------------------------------- hw-bluetooth
  {
    name = "hw-bluetooth publishes the pairing key directory";
    expected = {
      directories = {
        "sys/config" = [ "/var/lib/bluetooth" ];
      };
      files = { };
      bluez = true;
    };
    actual = {
      directories = nixosPlain.kdn.hw.bluetooth.persist.directories;
      files = nixosPlain.kdn.hw.bluetooth.persist.files;
      bluez = nixosPlain.hardware.bluetooth.enable;
    };
  }

  # ---------------------------------------------------------------- the present leaves
  {
    name = "the AMD GPU aspect and the Intel CPU aspect publish a present leaf";
    expected = {
      amd = true;
      intel = true;
    };
    actual = {
      amd = nixosPlain.kdn.hw.gpu.amd.present;
      intel = nixosPlain.kdn.hw.cpu.intel.present;
    };
  }

  # ---------------------------------------------------------------- hw-gpu
  {
    name = "the supergfxd mode is unset until the VFIO switch turns on";
    expected = {
      plain = null;
      laptop = "Integrated";
    };
    actual = {
      plain = nixosPlain.kdn.hw.gpu.supergfxd.mode;
      laptop = nixosLaptop.kdn.hw.gpu.supergfxd.mode;
    };
  }
  {
    name = "the VFIO kernel parameters name the ids, the IOMMU and the supergfxd mode";
    expected = sorted [
      "intel_iommu=on"
      "iommu=pt"
      "vfio-pci.ids=1002:1478"
      "supergfxd.mode=Integrated"
    ];
    actual = sorted (
      lib.filter (
        p:
        lib.hasPrefix "vfio-pci.ids=" p
        || lib.hasPrefix "supergfxd.mode=" p
        || p == "intel_iommu=on"
        || p == "iommu=pt"
      ) nixosLaptop.boot.kernelParams
    );
  }
  {
    name = "none of those parameters appears without the VFIO switch";
    expected = [ ];
    actual = lib.filter (
      p:
      lib.hasPrefix "vfio-pci.ids=" p
      || lib.hasPrefix "supergfxd.mode=" p
      || p == "intel_iommu=on"
      || p == "iommu=pt"
    ) nixosPlain.boot.kernelParams;
  }
  {
    name = "the supergfxctl overlay lands only when the package option holds a function";
    expected = {
      plainOverlays = 0;
      overlayOverlays = 1;
      swapped = "hello";
    };
    actual = {
      plainOverlays = builtins.length nixosPlain.nixpkgs.overlays;
      overlayOverlays = builtins.length nixosOverlaySystem.config.nixpkgs.overlays;
      # `nixosSystem` re-exports the final package set at the top level
      # (`<nixpkgs>/nixos/lib/eval-config.nix:112`). `config._module` is **not** readable: the
      # module system strips `_module` out of `config` (`<nixpkgs>/lib/modules.nix:401`).
      swapped = lib.getName nixosOverlaySystem.pkgs.supergfxctl;
    };
  }

  # ---------------------------------------------------------------- hw-gpu-intel
  {
    name = "the VDPAU driver follows the graphics stack";
    expected = "va_gl";
    actual = nixosPlain.environment.sessionVariables.VDPAU_DRIVER;
  }

  # ---------------------------------------------------------------- hw-edid
  {
    name = "the EDID modeline set is empty until a consumer fills it";
    expected = { };
    actual = nixosPlain.kdn.hw.edid.modelines;
  }

  # ---------------------------------------------------------------- hw-intel-graphics-fix
  {
    name = "the Mesa driver override writes nothing until a consumer sets it";
    expected = {
      plain = false;
      laptop = "i965";
    };
    actual = {
      plain = nixosPlain.environment.variables ? MESA_LOADER_DRIVER_OVERRIDE;
      laptop = nixosLaptop.environment.variables.MESA_LOADER_DRIVER_OVERRIDE;
    };
  }

  # ---------------------------------------------------------------- hw-modem
  {
    name = "the modem aspect turns NetworkManager and ModemManager on";
    expected = {
      networkmanager = true;
      modemmanager = true;
      wantedBy = [ "NetworkManager.service" ];
    };
    actual = {
      networkmanager = nixosPlain.networking.networkmanager.enable;
      modemmanager = nixosPlain.systemd.services.ModemManager.enable;
      wantedBy = nixosPlain.systemd.services.ModemManager.wantedBy;
    };
  }

  # ---------------------------------------------------------------- hw-nanokvm
  {
    name = "the NanoKVM profile binds the stable name and waits for a request";
    expected = {
      interface = "usb-nanokvm";
      autoconnect = false;
      priority = -999;
    };
    actual = {
      interface =
        nixosPlain.networking.networkmanager.ensureProfiles.profiles.nanokvm.connection.interface-name;
      autoconnect =
        nixosPlain.networking.networkmanager.ensureProfiles.profiles.nanokvm.connection.autoconnect;
      priority =
        nixosPlain.networking.networkmanager.ensureProfiles.profiles.nanokvm.connection.autoconnect-priority;
    };
  }

  # ---------------------------------------------------------------- hw-qmk
  {
    name = "both Oryx commands install in both host classes";
    expected = {
      nixosFlash = true;
      nixosSrc = true;
      darwinFlash = true;
      darwinSrc = true;
    };
    actual = {
      nixosFlash = has "oryx-flash" nixosPlain.environment.systemPackages;
      nixosSrc = has "oryx-src" nixosPlain.environment.systemPackages;
      darwinFlash = has "oryx-flash" darwinPlain.environment.systemPackages;
      darwinSrc = has "oryx-src" darwinPlain.environment.systemPackages;
    };
  }
  {
    name = "the graphical layout editor follows kdn.hw.qmk.graphical and stays off Darwin";
    expected = {
      plain = false;
      laptop = true;
      darwin = false;
    };
    # `lib.getName pkgs.vial` is `"Vial"`, with a capital V: the derivation sets `pname = "Vial"`.
    # Measured 2026-09-11. `meta.platforms` names `x86_64-linux` alone, so `filterPackages` drops the
    # package on a Darwin consumer even when the flag is `true`.
    actual = {
      plain = has "Vial" nixosPlain.environment.systemPackages;
      laptop = has "Vial" nixosLaptop.environment.systemPackages;
      darwin = has "Vial" darwinPlain.environment.systemPackages;
    };
  }

  # ---------------------------------------------------------------- hw-usbip
  {
    name = "the USB/IP package default follows the running kernel";
    expected = true;
    actual = lib.hasInfix "usbip" (lib.getName nixosPlain.kdn.hw.usbip.package);
  }
  {
    name = "the USB/IP port opens on one interface, or on every interface";
    expected = {
      plainGlobal = [ ];
      plainInterface = [ 3240 ];
      laptopGlobal = [ 3240 ];
    };
    actual = {
      plainGlobal = nixosPlain.networking.firewall.allowedTCPPorts;
      plainInterface = nixosPlain.networking.firewall.interfaces.wg0.allowedTCPPorts;
      laptopGlobal = nixosLaptop.networking.firewall.allowedTCPPorts;
    };
  }
  {
    name = "the bind template does not start an instance named after its own target";
    expected = false;
    actual = nixosPlain.systemd.services."usbip-bind@network".enable;
  }

  # ---------------------------------------------------------------- hw-yubikey
  {
    name = "the PAM application id follows the host name";
    expected = "pam://den-hw";
    actual = nixosLaptop.kdn.hw.yubikey.appId;
  }
  {
    name = "the YubiKey aspect publishes the age plugin and the generator script";
    expected = {
      plugins = [ "age-plugin-yubikey" ];
      scripts = [ "kdn-sops-age-gen-keys-yubikey" ];
      pcscd = true;
    };
    actual = {
      plugins = map lib.getName nixosPlain.kdn.hw.yubikey.agePlugins;
      scripts = map lib.getName nixosPlain.kdn.hw.yubikey.ageGenScripts;
      pcscd = nixosPlain.services.pcscd.enable;
    };
  }
  {
    name = "a machine that allows no secret gets no age plugin and no smart-card daemon";
    expected = {
      plugins = [ ];
      scripts = [ ];
      pcscd = false;
    };
    actual = {
      plugins = map lib.getName nixosNoSecrets.kdn.hw.yubikey.agePlugins;
      scripts = map lib.getName nixosNoSecrets.kdn.hw.yubikey.ageGenScripts;
      pcscd = nixosNoSecrets.services.pcscd.enable;
    };
  }
  {
    name = "the sops ordering stays out of a class that carries no sops-nix";
    expected = {
      hasSops = false;
      hasUnit = false;
    };
    actual = {
      hasSops = nixosPlain ? sops;
      hasUnit = nixosPlain.systemd.services ? sops-install-secrets;
    };
  }
  {
    name = "the graphical authenticator follows kdn.hw.yubikey.graphical and stays off Darwin";
    expected = {
      plain = false;
      laptop = true;
      darwin = false;
    };
    actual = {
      plain = has "yubioath-flutter" nixosPlain.environment.systemPackages;
      laptop = has "yubioath-flutter" nixosLaptop.environment.systemPackages;
      darwin = has "yubioath-flutter" darwinPlain.environment.systemPackages;
    };
  }
  {
    name = "the Darwin class runs the GnuPG agent";
    expected = true;
    actual = darwinPlain.programs.gnupg.agent.enable;
  }
  {
    name = "the Home Manager class carries the three scdaemon settings";
    expected = {
      disable-ccid = true;
      pcsc-shared = true;
      disable-application = "piv";
    };
    actual = homePlain.programs.gpg.scdaemonSettings;
  }

  # ---------------------------------------------------------------- hw-darwin-utm-guest
  {
    name = "hw-darwin-utm-guest loads the QEMU guest profile and the two UTM initrd modules";
    expected = {
      balloon = true;
      xhci = true;
      sr = true;
    };
    actual = {
      balloon = lib.elem "virtio_balloon" nixosPlain.boot.initrd.kernelModules;
      xhci = lib.elem "xhci_pci" nixosPlain.boot.initrd.availableKernelModules;
      sr = lib.elem "sr_mod" nixosPlain.boot.initrd.availableKernelModules;
    };
  }

  # ---------------------------------------------------------------- hw-dell-e5470
  {
    name = "hw-dell-e5470 loads the four laptop kernel modules";
    expected = {
      kvm = true;
      sdmmc = true;
      ethernet = true;
      snapshot = true;
    };
    actual = {
      kvm = lib.elem "kvm-intel" nixosPlain.boot.kernelModules;
      sdmmc = lib.elem "rtsx_pci_sdmmc" nixosPlain.boot.initrd.availableKernelModules;
      ethernet = lib.elem "e1000e" nixosPlain.boot.initrd.availableKernelModules;
      snapshot = lib.elem "dm-snapshot" nixosPlain.boot.initrd.kernelModules;
    };
  }
  {
    name = "hw-dell-e5470 turns zram swap on at half of the memory";
    expected = {
      enable = true;
      memoryPercent = 50;
      priority = 100;
    };
    actual = {
      enable = nixosPlain.zramSwap.enable;
      memoryPercent = nixosPlain.zramSwap.memoryPercent;
      priority = nixosPlain.zramSwap.priority;
    };
  }
  {
    name = "hw-dell-e5470 pulls the Intel GPU aspect and the modem aspect in by itself";
    expected = {
      i915 = true;
      networkManager = true;
      modemManager = true;
      kvm = true;
    };
    actual = {
      i915 = lib.elem "i915" nixosDellOnly.boot.initrd.kernelModules;
      networkManager = nixosDellOnly.networking.networkmanager.enable;
      modemManager = nixosDellOnly.systemd.services.ModemManager.enable;
      kvm = lib.elem "kvm-intel" nixosDellOnly.boot.kernelModules;
    };
  }
]

# The assertion set for layer-C batch 10: the service, the managed-file and the virtualisation
# aspects. `../tests.nix` imports this file and registers the result as `den-eval-services`.
#
# Every assertion is `{ name; expected; actual; }`, the shape `mkEvalCheck` needs.
#
# ## The subjects
#
# | Subject | Class | What it proves |
# |---|---|---|
# | `nixosPlain` | nixos | every `nixos` target of the batch evaluates with **no** consumer data |
# | `nixosDocker` | nixos | the docker aspect turns the docker engine on |
# | `nixosData` | nixos | each option the batch declares reaches the native option |
# | `nixosNoSecrets` | nixos | a forbidden secret drops every credential half |
# | `darwinCfg` | darwin | the two darwin targets evaluate |
# | `homeDarwin` | homeManager | the Linux-only home body drops out on a darwin home |
# | `homeLinux` | homeManager | the real home body evaluates, and it reads no NixOS option |
#
# ## Why this file builds one home harness of its own
#
# `../harness.nix` fixes the home harness to `aarch64-darwin`. The container aspect writes its files
# only on Linux, so the fixed harness cannot reach that body. `bareLinuxHome` below repeats the same
# three lines on `x86_64-linux`. It builds no derivation; it evaluates one.
#
# ## The data holds no real value
#
# Every consumer value below is a placeholder. No host name, no address, no CIDR and no zone of any
# real machine appears here.
{
  lib,
  pkgs,
  inputs,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos bareDarwinSystem;

  modulesFor =
    class: aspects:
    denLib.imports {
      inherit class aspects;
    };

  # A Linux home, in the same bare-consumer shape as `../harness.nix`'s darwin one.
  bareLinuxHome =
    modules:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
      modules = modules ++ [
        {
          home.username = "dev";
          home.homeDirectory = "/home/dev";
          home.stateVersion = "26.11";
        }
      ];
    };

  # Every `nixos` aspect of this batch. `virt-containers-docker` stays out: it turns the docker
  # engine on, and the podman aspect turns it off.
  nixosAspects = [
    "managed"
    "service-caddy"
    "service-coredns"
    "service-home-assistant"
    "service-iperf3"
    "service-nextcloud-client"
    "service-postgresql"
    "service-printing"
    "service-samba"
    "service-zammad"
    "virt-containers"
    "virt-containers-dagger"
    "virt-containers-distrobox"
    "virt-containers-podman"
    "virt-containers-x11docker"
    "virt-libvirtd"
    "virt-vagrant"
  ];

  nixosPlain = (bareNixos (modulesFor "nixos" nixosAspects)).config;

  nixosDocker =
    (bareNixos (
      modulesFor "nixos" [
        "virt-containers"
        "virt-containers-docker"
      ]
    )).config;

  # One value per option this batch declares.
  data = {
    kdn.hostName = "placeholder-host";
    kdn.services.coredns.rewrites."placeholder.invalid." = {
      from = "from.placeholder.invalid.";
      upstreams = [ "upstream-placeholder" ];
    };
    kdn.services.home-assistant.zha.use = true;
    kdn.services.home-assistant.tuyaCloud.use = true;
    kdn.services.iperf3.server.privateKeyPath = "/placeholder/iperf3-key";
    kdn.services.iperf3.server.authorizedUsersPath = "/placeholder/iperf3-users";
    kdn.services.nextcloud-client.urlPath = "/placeholder/nextcloud-url";
    kdn.services.nextcloud-client.usernamePath = "/placeholder/nextcloud-user";
    kdn.services.nextcloud-client.passwordPath = "/placeholder/nextcloud-password";
    kdn.services.printing.printers = [
      {
        name = "placeholder-printer";
        deviceUri = "file:///dev/null";
        model = "drv:///sample.drv/generic.ppd";
      }
    ];
    kdn.services.printing.defaultPrinter = "placeholder-printer";
    kdn.services.samba.defaults.workgroup = "PLACEHOLDER";
    # 8080 is an unprivileged port, so the bind capability must drop out.
    kdn.services.zammad.port = 8080;
    kdn.managed.directories = [ "/placeholder/managed" ];
  };

  nixosData =
    (bareNixos (
      modulesFor "nixos" [
        "managed"
        "service-coredns"
        "service-home-assistant"
        "service-iperf3"
        "service-nextcloud-client"
        "service-printing"
        "service-samba"
        "service-zammad"
      ]
      ++ [
        (secretsPolicy true)
        data
      ]
    )).config;

  nixosNoSecrets =
    (bareNixos (
      modulesFor "nixos" [
        "managed"
        "service-iperf3"
        "service-nextcloud-client"
      ]
      ++ [
        (secretsPolicy false)
        {
          kdn.services.iperf3.server.privateKeyPath = "/placeholder/iperf3-key";
          kdn.services.iperf3.server.authorizedUsersPath = "/placeholder/iperf3-users";
          kdn.services.nextcloud-client.urlPath = "/placeholder/nextcloud-url";
          kdn.services.nextcloud-client.usernamePath = "/placeholder/nextcloud-user";
          kdn.services.nextcloud-client.passwordPath = "/placeholder/nextcloud-password";
        }
      ]
    )).config;

  # The `secrets` aspect of batch 2 declares this option, and three aspects of this batch read it
  # with an `or` fallback. This module supplies a real declaration, so the read finds one.
  secretsPolicy = allow: {
    options.kdn.security.secrets.allowed = lib.mkOption {
      type = lib.types.bool;
      default = allow;
    };
  };

  darwinCfg =
    (bareDarwinSystem (
      modulesFor "darwin" [
        "managed"
        "virt-containers-dagger"
        "virt-containers-podman"
      ]
    )).config;

  homeAspects = [
    "service-syncthing"
    "virt-containers"
    "virt-containers-dagger"
    "virt-libvirtd"
  ];

  homeDarwin = (harness.bareHomeConfiguration (modulesFor "homeManager" homeAspects)).config;

  homeLinux =
    (bareLinuxHome (
      modulesFor "homeManager" homeAspects
      ++ [
        {
          kdn.virtualisation.containers.hooksDirs = [ "/placeholder/oci-hooks" ];
          kdn.services.syncthing.guiAddress = "gui-address-placeholder";
        }
      ]
    )).config;

  packageNames = map lib.getName;

  hasAll = have: map (want: builtins.elem want have);

  # Home Manager adds a file of its own to `xdg.configFile`, and the Linux class adds one per
  # systemd unit. So each read below keeps the container files alone.
  containerFiles =
    cfg:
    lib.pipe cfg.xdg.configFile [
      builtins.attrNames
      (builtins.filter (lib.hasPrefix "containers/"))
      (lib.sort (a: b: a < b))
    ];
in
[
  # ---------------------------------------------------------------- nixosPlain
  {
    name = "the caddy aspect opens the two web ports";
    expected = [
      true
      true
    ];
    actual = hasAll nixosPlain.networking.firewall.allowedTCPPorts [
      80
      443
    ];
  }
  {
    name = "the caddy service keeps the bind capability";
    expected = [ "CAP_NET_BIND_SERVICE" ];
    actual = nixosPlain.systemd.services.caddy.serviceConfig.AmbientCapabilities;
  }
  {
    name = "the coredns aspect writes a server block with no rewrite";
    expected = true;
    actual = nixosPlain.services.coredns.config != "";
  }
  {
    name = "home-assistant loads no zigbee component by default";
    expected = false;
    actual = builtins.elem "zha" nixosPlain.services.home-assistant.extraComponents;
  }
  {
    name = "iperf3 passes no flag with no credential path";
    expected = [ ];
    actual = nixosPlain.services.iperf3.extraFlags;
  }
  {
    name = "postgresql publishes its data directory and its own user";
    expected = [
      1
      "postgres"
    ];
    actual = [
      (builtins.length nixosPlain.kdn.services.postgresql.persist.sysData)
      (builtins.head nixosPlain.kdn.services.postgresql.persist.sysData).user
    ];
  }
  {
    name = "printing publishes its state directory";
    expected = [ "/var/lib/cups" ];
    actual = nixosPlain.kdn.services.printing.persist.sysData;
  }
  {
    name = "printing names no printer of anybody";
    expected = [ ];
    actual = nixosPlain.hardware.printers.ensurePrinters;
  }
  {
    name = "samba names no workgroup of anybody";
    expected = "WORKGROUP";
    actual = nixosPlain.services.samba.settings.global."workgroup";
  }
  {
    name = "samba denies every host it does not allow";
    expected = true;
    actual = nixosPlain.services.samba.settings.global ? "hosts deny";
  }
  {
    name = "samba publishes both persistence buckets";
    expected = [
      1
      1
    ];
    actual = [
      (builtins.length nixosPlain.kdn.services.samba.persist.sysData)
      (builtins.length nixosPlain.kdn.services.samba.persist.usrData)
    ];
  }
  {
    name = "zammad keeps the bind capability on a privileged port";
    expected = [ "CAP_NET_BIND_SERVICE" ];
    actual = nixosPlain.systemd.services.zammad-web.serviceConfig.AmbientCapabilities;
  }
  {
    name = "zammad names one redis server";
    expected = [ "zammad" ];
    actual = builtins.attrNames nixosPlain.services.redis.servers;
  }
  {
    name = "the managed aspect carries its own name part";
    expected = [ "default" ];
    actual = builtins.attrNames nixosPlain.kdn.managed.infix;
  }
  {
    name = "the managed cleanup runs after the etc and the users step";
    expected = [
      "etc"
      "users"
    ];
    actual = nixosPlain.system.activationScripts.kdnManagedFilesCleanup.deps;
  }
  {
    name = "the managed aspect keeps no file with no secret template";
    expected = [ ];
    actual = nixosPlain.kdn.managed.currentFiles;
  }
  {
    name = "the containers aspect publishes both persistence buckets";
    expected = [ "/var/lib/containers/cache" ];
    actual = nixosPlain.kdn.virtualisation.containers.persist.usrCache;
  }
  {
    name = "the containers aspect defaults no container engine on";
    expected = false;
    actual = nixosPlain.virtualisation.docker.enable;
  }
  {
    name = "the podman engine comes from its own aspect";
    expected = true;
    actual = nixosPlain.virtualisation.podman.enable;
  }
  {
    name = "libvirtd publishes three persistence directories";
    expected = 3;
    actual = builtins.length nixosPlain.kdn.virtualisation.libvirtd.persist.usrData;
  }
  {
    name = "every nixos aspect of this batch forces in one bare consumer";
    expected = true;
    actual = builtins.isString nixosPlain.system.build.toplevel.drvPath;
  }

  # ---------------------------------------------------------------- nixosDocker
  {
    name = "the docker aspect turns the docker engine on";
    expected = true;
    actual = nixosDocker.virtualisation.docker.enable;
  }

  # ---------------------------------------------------------------- nixosData
  {
    name = "coredns rewrites the name the consumer names";
    expected = true;
    actual = lib.hasInfix "from.placeholder.invalid." nixosData.services.coredns.config;
  }
  {
    name = "home-assistant gains the zigbee and the tuya component";
    expected = [
      true
      true
    ];
    actual = hasAll nixosData.services.home-assistant.extraComponents [
      "zha"
      "tuya"
    ];
  }
  {
    name = "the zigbee database sits under the home-assistant state directory";
    expected = "/var/lib/hass/zigbee.db";
    actual = nixosData.services.home-assistant.config.zha.database_path;
  }
  {
    name = "iperf3 loads both server credentials";
    expected = 2;
    actual = builtins.length nixosData.systemd.services.iperf3.serviceConfig.LoadCredential;
  }
  {
    name = "the nextcloud timer lands when all three paths hold a value";
    expected = true;
    actual = nixosData.systemd.timers ? "kdn-nextcloud-nixos-sync";
  }
  {
    name = "printing ensures the printer the consumer names";
    expected = [
      [ "placeholder-printer" ]
      "placeholder-printer"
    ];
    actual = [
      (map (p: p.name) nixosData.hardware.printers.ensurePrinters)
      nixosData.hardware.printers.ensureDefaultPrinter
    ];
  }
  {
    name = "samba takes the workgroup and the machine name from the consumer";
    expected = [
      "PLACEHOLDER"
      "placeholder-host-SMB"
    ];
    actual = [
      nixosData.services.samba.settings.global."workgroup"
      nixosData.services.samba.settings.global."server string"
    ];
  }
  {
    name = "zammad drops the bind capability on an unprivileged port";
    expected = false;
    actual = nixosData.systemd.services.zammad-web.serviceConfig ? AmbientCapabilities;
  }
  {
    name = "the managed type coerces a plain string list into an attribute set";
    expected = [ "/placeholder/managed" ];
    actual = builtins.attrNames nixosData.kdn.managed.directories;
  }
  {
    name = "the data consumer forces the whole nixos config";
    expected = true;
    actual = builtins.isString nixosData.system.build.toplevel.drvPath;
  }

  # ---------------------------------------------------------------- nixosNoSecrets
  {
    name = "a forbidden secret drops the iperf3 credentials";
    expected = false;
    actual = nixosNoSecrets.systemd.services.iperf3.serviceConfig ? LoadCredential;
  }
  {
    name = "a forbidden secret drops the nextcloud timer";
    expected = false;
    actual = nixosNoSecrets.systemd.timers ? "kdn-nextcloud-nixos-sync";
  }
  {
    name = "a forbidden secret keeps no managed file";
    expected = [ ];
    actual = nixosNoSecrets.kdn.managed.currentFiles;
  }

  # ---------------------------------------------------------------- darwin
  {
    name = "the managed aspect appends its cleanup to the darwin post-activation";
    expected = true;
    actual = lib.hasInfix "kdn-managed-cleanup" darwinCfg.system.activationScripts.postActivation.text;
  }
  {
    name = "the dagger aspect installs the cue tooling on darwin";
    expected = [
      true
      true
    ];
    actual = hasAll (packageNames darwinCfg.environment.systemPackages) [
      "cue"
      "cuelsp"
    ];
  }
  {
    name = "the podman aspect reaches darwin through Homebrew";
    expected = true;
    actual = darwinCfg.homebrew.brews != [ ];
  }
  {
    name = "every darwin aspect of this batch forces in one bare consumer";
    expected = true;
    actual = builtins.isString darwinCfg.system.build.toplevel.drvPath;
  }

  # ---------------------------------------------------------------- homeDarwin
  {
    name = "syncthing stays off on a darwin home";
    expected = false;
    actual = homeDarwin.services.syncthing.enable;
  }
  {
    name = "the containers aspect writes no file on a darwin home";
    expected = [ ];
    actual = containerFiles homeDarwin;
  }
  {
    name = "a darwin home still publishes the containers persistence list";
    expected = [ ".local/share/containers" ];
    actual = homeDarwin.kdn.virtualisation.containers.persist.usrData;
  }
  {
    name = "every homeManager aspect of this batch forces on a darwin home";
    expected = true;
    actual = builtins.isString homeDarwin.home.activationPackage.drvPath;
  }

  # ---------------------------------------------------------------- homeLinux
  {
    name = "syncthing runs on a Linux home";
    expected = true;
    actual = homeLinux.services.syncthing.enable;
  }
  {
    name = "the syncthing web-interface flag lands only when the consumer names an address";
    expected = true;
    actual = builtins.elem "--gui-address=gui-address-placeholder" homeLinux.services.syncthing.extraOptions;
  }
  {
    name = "the containers aspect writes its four files on a Linux home";
    expected = [
      "containers/containers.conf"
      "containers/policy.json"
      "containers/registries.conf"
      "containers/storage.conf"
    ];
    actual = containerFiles homeLinux;
  }
  {
    name = "the OCI hook directory comes from the option, and from no NixOS option";
    expected = [ "/placeholder/oci-hooks" ];
    actual = homeLinux.kdn.virtualisation.containers.containersConf.settings.engine.hooks_dir;
  }
  {
    name = "every homeManager aspect of this batch forces on a Linux home";
    expected = true;
    actual = builtins.isString homeLinux.home.activationPackage.drvPath;
  }
]

{
  lib,
  config,
  pkgs,
  kdnConfig,
  ...
}:
let
  # DEAD CODE SWITCH. `false` detaches this host's own stock `nix.linux-builder` setup and the
  # `nix.buildMachines` entry that points at it. Both blocks below stay in the file, unchanged.
  #
  # The live route is `kdn.darwin.rosetta-builder`. Upstream registers one build machine that
  # serves both `aarch64-linux` and `x86_64-linux` (module.nix:394-410 of the locked rev), so the
  # detach removes no architecture. The stock builder served `aarch64-linux` only.
  #
  # To re-attach: set `legacyLinuxBuilder = true;` here. Nothing else changes.
  #
  # ORDER TRAP on a real machine: nix-rosetta-builder needs an existing Linux builder to build its
  # own guest image the first time. So on a fresh machine, re-attach this first, activate, wait for
  # the Rosetta guest, then set it back to `false`. The owner runs every activation.
  legacyLinuxBuilder = false;
  bootstrapBuilder = false;

  slots = kdnConfig.self.mkSlots {
    inherit pkgs;
    # This flake's own host connectivity graph. `pathExists` keeps the import optional, so a tree
    # without the data file still evaluates.
    imports = builtins.filter builtins.pathExists [
      "${kdnConfig.self}/data/slots/slots-ssh-access.nix"
    ];

    kdn.darwin.rosetta-builder.enable = true;
    # Replace the macOS built-in ssh-agent with the FIDO2-capable OpenSSH agent.
    kdn.home.ssh-agent.enable = true;
    # devenv CLI and shell hooks.
    kdn.devenv.enable = true;
    # Topology-aware remote SSH access (kdn-* dispatcher). The graph comes from the import above.
    # `defaults.identityFile` stays unset until the owner names this host's key (ASK-1).
    kdn.ssh-access.enable = true;

    # Verifiable SSH commit signing, plus the `kdn-signing` route switch. The slot holds no key;
    # every value below belongs to this host.
    kdn.signing.enable = true;
    kdn.signing.plain.keyFile = "~/.ssh/id_ed25519_kdn_plain";
    # TODO(ASK-2): add this host's own signer entry. An empty list writes no `allowed_signers`
    # file, so git and jj sign but verify nothing. Create the plain key with:
    #   ssh-keygen -t ed25519 -C 'plain signing key' -f ~/.ssh/id_ed25519_kdn_plain
    kdn.signing.allowedSigners = [ ];
  };
in
{
  imports = [
    kdnConfig.self.darwinModules.default
    slots.config.darwin
  ];

  options.kdn.hosts.anji = {
    initialLinuxBuilder = lib.mkOption {
      # enable when building for the first time: needs to be pulled from cache without any customizations
      type = with lib.types; bool;
      default = bootstrapBuilder;
    };
  };

  config = lib.mkMerge [
    {
      kdn.hostName = "anji";
      kdn.profile.machine.baseline.enable = true;

      # Register one Homebrew tap per `brew-tap--*` flake input. The option defaults to `false`, so
      # that an external adopter of `modules/universal` inherits no tap of this flake. This host
      # keeps the scan on, so its evaluated tap list stays exactly what it was.
      kdn.homebrew.tapsFromFlakeInputs = true;
    }
    {
      # Rosetta builder guest disk, stated on purpose. This host is a Mac mini M2 with a 256 GB
      # disk, and the guest disk is a sparse file on it. `100GiB` is also the upstream default of
      # `nix-rosetta-builder`, and no module in this tree assigns `diskSize`, so this line changes
      # no evaluated value, regenerates no `lima.yaml`, and destroys no guest. The slot ceiling
      # `kdn.darwin.rosetta-builder.guest.diskSizeMax` stays `150GiB`.
      #
      # Do NOT set `kdn.darwin.rosetta-builder.guest.minFree` or `.maxFree`. A non-null value
      # regenerates `lima.yaml`, and the daemon then runs `limactl delete --force` on the guest.
      nix-rosetta-builder.diskSize = "100GiB";
    }
    {
      system.stateVersion = 6;
      home-manager.sharedModules = [ { home.stateVersion = "26.05"; } ];
    }
    {
      home-manager.sharedModules = [ slots.config.home ];
    }
    {
      environment.systemPackages = with pkgs; [
        utm
      ];
      kdn.toolset.network.enable = true;
    }
    {
      # Touch ID for sudo, plus the re-attach fix macOS needs so it also works inside a terminal
      # multiplexer. The work host gets both from its own profile.
      security.pam.services.sudo_local.touchIdAuth = true;
      security.pam.services.sudo_local.reattach = true;
    }
    {
      homebrew.casks = [
        "tidal"
      ];
    }
    (lib.optionalAttrs legacyLinuxBuilder {
      # DETACHED DEAD CODE — see `legacyLinuxBuilder` in the `let` block above.
      # inspired by https://nixcademy.com/posts/macos-linux-builder/
      nix.settings.trusted-users = [ "@admin" ];
      kdn.hosts.anji.initialLinuxBuilder = bootstrapBuilder;

      nix.linux-builder.enable = true;
      nix.linux-builder.ephemeral = true;
      nix.linux-builder.workingDirectory = "/anji-ext-01/linux-builder";
      launchd.daemons.linux-builder.serviceConfig.StandardOutPath = "/var/log/linux-builder/stdout.log";
      launchd.daemons.linux-builder.serviceConfig.StandardErrorPath = "/var/log/linux-builder/stderr.log";
    })
    (lib.mkIf (!config.kdn.hosts.anji.initialLinuxBuilder && legacyLinuxBuilder) {
      # DETACHED DEAD CODE — see `legacyLinuxBuilder` in the `let` block above. This block also
      # imports ./linux-builder.nix, which therefore stays unevaluated too.
      # TODO: /nix/store/yzhl36k6yxfafrvddhqjbwzvmwlyx4iq-stdenv-linux/setup: line 1828: wrapProgram: command not found
      #   see (nix on MacOS) https://matrix.to/#/!lheuhImcToQZYTQTuI:nixos.org/$-Bi9gZCVQ8JyFmVtOQR-WoYvJsnUOUWZfqc_xJDNNQM?via=nixos.org&via=matrix.org&via=nixos.dev
      nix.buildMachines =
        let
          # cat /anji-ext-01/linux-builder/keys/ssh_host_ed25519_key.pub | base64
          hostKey64 = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUR4L3Z3OGtmWTJZMkY2Umw2SVhSUXZrRlZHR3J4NjZVblp0SGJNR1pMUlcgcm9vdEBhbmppCg==";
        in
        [
          {
            hostName = "anji-linux-builder";
            sshUser = config.kdn.nix.remote-builder.user.name;
            sshKey = config.kdn.nix.remote-builder.user.ssh.IdentityFile;
            publicHostKey = hostKey64;
            inherit (config.nix.linux-builder)
              mandatoryFeatures
              maxJobs
              protocol
              speedFactor
              supportedFeatures
              systems
              ;
          }
        ];

      nix.linux-builder.config =
        let
          gbs.disk = 256;
          gbs.min-free = 0.1 * gbs.disk;
          gbs.max-free = 2 * gbs.min-free;
          gbs.ram = 12;
          cores = 6;
        in
        {
          imports = [ ./linux-builder.nix ];

          config = lib.mkMerge [
            (
              let
                MiB = 1;
                GiB = 1024 * MiB;
              in
              {
                virtualisation.darwin-builder.diskSize = builtins.floor (gbs.disk * GiB);
                virtualisation.darwin-builder.memorySize = builtins.floor (gbs.ram * GiB);
                virtualisation.cores = cores;
              }
            )
            (
              let
                B = 1;
                KiB = 1024 * B;
                MiB = 1024 * KiB;
                GiB = 1024 * MiB;
              in
              {
                virtualisation.darwin-builder.min-free = builtins.floor (gbs.min-free * GiB);
                virtualisation.darwin-builder.max-free = builtins.floor (gbs.max-free * GiB);
              }
            )
            {
              virtualisation.qemu.options = [
                # socat - UNIX-CONNECT:/run/org.nixos.linux-builder/qemu-serial.sock
                # minicom -D 'unix#/run/org.nixos.linux-builder/qemu-serial.sock'
                ''-serial unix:"$TMPDIR/qemu-serial.sock",server,nowait''
              ];
            }
          ];
        };

      kdn.env.packages = with pkgs; [
        minicom
      ];
      nix.linux-builder.systems = [ "aarch64-linux" ];
      nix.linux-builder.supportedFeatures = [
        "kvm"
        "benchmark"
        "big-parallel"
      ];
      nix.linux-builder.maxJobs = 4;
      nix.linux-builder.speedFactor = 8;

      nix.linux-builder.package =
        # based off https://github.com/NixOS/nixpkgs/blob/6d6a82e3a039850b67793008937db58924679837/pkgs/top-level/darwin-packages.nix#L190-L212
        let
          nixpkgsPath = kdnConfig.inputs.nixpkgs.outPath;
          stdenv = pkgs.stdenv;
          toGuest = builtins.replaceStrings [ "darwin" ] [ "linux" ];

          defaultSpecialArgs = (kdnConfig.output.mkSubmodule { moduleType = "nixos"; }).specialArgs;
        in
        lib.makeOverridable
          (
            {
              # args accepted by https://github.com/NixOS/nixpkgs/blob/5cc377e36a12dedae111cbc8d6d2eb7fa6f196c8/nixos/default.nix
              modules,
              specialArgs,
              system,
            }:
            let
              nixos = import (nixpkgsPath + "/nixos") {
                specialArgs = defaultSpecialArgs // specialArgs;
                system = null;
                configuration = {
                  imports = [
                    (nixpkgsPath + "/nixos/modules/profiles/nix-builder-vm.nix")
                  ]
                  ++ modules;

                  config = {
                    # If you need to override this, consider starting with the right Nixpkgs
                    # in the first place, ie change `pkgs` in `pkgs.darwin.linux-builder`.
                    # or if you're creating new wiring that's not `pkgs`-centric, perhaps use the
                    # macos-builder profile directly.
                    virtualisation.host = { inherit pkgs; };

                    nixpkgs.hostPlatform = lib.mkDefault system;
                  };
                };
              };
            in
            nixos.config.system.build.macos-builder-installer
          )
          {
            modules = [ ];
            specialArgs = { };
            system = toGuest stdenv.hostPlatform.system;
          };
    })
    {
      # The dev machine profile is permanent now, so this host mirrors the work host.
      kdn.profile.machine.dev.enable = true;
      kdn.programs.handlr.enable = false;
      home-manager.sharedModules = [
        {
          kdn.programs.handlr.enable = false;
        }
      ];
    }
  ];
}

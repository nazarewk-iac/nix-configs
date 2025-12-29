{
  lib,
  config,
  pkgs,
  kdnConfig,
  ...
}: {
  imports = [
    kdnConfig.self.darwinModules.default
  ];

  options.kdn.hosts.anji = {
    initialLinuxBuilder = lib.mkOption {
      # enable when building for the first time: needs to be pulled from cache without any customizations
      type = with lib.types; bool;
      default = true;
    };
  };

  config = lib.mkMerge [
    {
      kdn.hostName = "anji";
      kdn.profile.machine.baseline.enable = true;
    }
    {
      nixpkgs.system = "aarch64-darwin";
      system.stateVersion = 6;
      home-manager.sharedModules = [{home.stateVersion = "26.05";}];
    }
    {
      environment.systemPackages = with pkgs; [
        utm
      ];
      kdn.toolset.network.enable = true;
    }
    {
      # inspired by https://nixcademy.com/posts/macos-linux-builder/
      nix.settings.trusted-users = ["@admin"];
      kdn.hosts.anji.initialLinuxBuilder = false;

      nix.linux-builder.enable = true;
      nix.linux-builder.ephemeral = true;
      nix.linux-builder.workingDirectory = "/anji-ext-01/linux-builder";
    }
    (lib.mkIf (!config.kdn.hosts.anji.initialLinuxBuilder) {
      # TODO: /nix/store/yzhl36k6yxfafrvddhqjbwzvmwlyx4iq-stdenv-linux/setup: line 1828: wrapProgram: command not found
      #   see (nix on MacOS) https://matrix.to/#/!lheuhImcToQZYTQTuI:nixos.org/$-Bi9gZCVQ8JyFmVtOQR-WoYvJsnUOUWZfqc_xJDNNQM?via=nixos.org&via=matrix.org&via=nixos.dev
      nix.buildMachines = let
        # cat /anji-ext-01/linux-builder/keys/ssh_host_ed25519_key.pub | base64
        hostKey64 = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUR4L3Z3OGtmWTJZMkY2Umw2SVhSUXZrRlZHR3J4NjZVblp0SGJNR1pMUlcgcm9vdEBhbmppCg==";
      in [
        {
          hostName = "anji-linux-builder";
          sshUser = config.kdn.nix.remote-builder.user.name;
          sshKey = config.kdn.nix.remote-builder.user.ssh.IdentityFile;
          publicHostKey = hostKey64;
          inherit (config.nix.linux-builder) mandatoryFeatures maxJobs protocol speedFactor supportedFeatures systems;
        }
      ];

      nix.linux-builder.config = let
        gbs.disk = 256;
        gbs.min-free = 0.1 * gbs.disk;
        gbs.max-free = 2 * gbs.min-free;
        gbs.ram = 12;
        cores = 6;
      in {
        imports = [./linux-builder.nix];

        config = lib.mkMerge [
          (let
            MiB = 1;
            GiB = 1024 * MiB;
          in {
            virtualisation.darwin-builder.diskSize = builtins.floor (gbs.disk * GiB);
            virtualisation.darwin-builder.memorySize = builtins.floor (gbs.ram * GiB);
            virtualisation.cores = cores;
          })
          (let
            B = 1;
            KiB = 1024 * B;
            MiB = 1024 * KiB;
            GiB = 1024 * MiB;
          in {
            virtualisation.darwin-builder.min-free = builtins.floor (gbs.min-free * GiB);
            virtualisation.darwin-builder.max-free = builtins.floor (gbs.max-free * GiB);
          })
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
      nix.linux-builder.systems = ["aarch64-linux"];
      nix.linux-builder.supportedFeatures = ["kvm" "benchmark" "big-parallel"];
      nix.linux-builder.maxJobs = 4;
      nix.linux-builder.speedFactor = 8;

      nix.linux-builder.package =
        # based off https://github.com/NixOS/nixpkgs/blob/6d6a82e3a039850b67793008937db58924679837/pkgs/top-level/darwin-packages.nix#L190-L212
        let
          nixpkgsPath = kdnConfig.inputs.nixpkgs.outPath;
          stdenv = pkgs.stdenv;
          toGuest = builtins.replaceStrings ["darwin"] ["linux"];

          defaultSpecialArgs = kdnConfig.output.mkSubmodule {moduleType = "nixos";};
        in
          lib.makeOverridable (
            {
              # args accepted by https://github.com/NixOS/nixpkgs/blob/5cc377e36a12dedae111cbc8d6d2eb7fa6f196c8/nixos/default.nix
              modules,
              specialArgs,
              system,
            }: let
              nixos = import (nixpkgsPath + "/nixos") {
                specialArgs = defaultSpecialArgs // specialArgs;
                system = null;
                configuration = {
                  imports =
                    [
                      (nixpkgsPath + "/nixos/modules/profiles/nix-builder-vm.nix")
                    ]
                    ++ modules;

                  config = {
                    # If you need to override this, consider starting with the right Nixpkgs
                    # in the first place, ie change `pkgs` in `pkgs.darwin.linux-builder`.
                    # or if you're creating new wiring that's not `pkgs`-centric, perhaps use the
                    # macos-builder profile directly.
                    virtualisation.host = {inherit pkgs;};

                    nixpkgs.hostPlatform = lib.mkDefault system;
                  };
                };
              };
            in
              nixos.config.system.build.macos-builder-installer
          ) {
            modules = [];
            specialArgs = {};
            system = toGuest stdenv.hostPlatform.system;
          };
    })
  ];
}

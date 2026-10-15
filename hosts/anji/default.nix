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
  # own guest image the first time. The Rosetta guest image is a plain `aarch64-linux` derivation,
  # and it is not substitutable, so the switch that first builds it needs a Linux builder that is
  # already running. The stock `nix.linux-builder` is that builder, and it starts only at
  # activation. So a generation that holds both cannot build the Rosetta image: the build phase
  # runs before the stock builder is up.
  #
  # The bootstrap is therefore three switches, and the two flags below are independent on purpose:
  #
  #   1. `legacyLinuxBuilder = true; rosettaBuilder = false;`  — stock builder on, Rosetta off.
  #      Switch. The stock builder comes up.
  #   2. `legacyLinuxBuilder = true; rosettaBuilder = true;`   — both on. Switch. The build phase
  #      dispatches the Rosetta image to the now-running stock builder. Both guests run.
  #   3. `legacyLinuxBuilder = false; rosettaBuilder = true;`  — stock builder off, Rosetta on.
  #      Switch. The Rosetta guest keeps its already-built image.
  #
  # The owner runs every activation. The stock builder's working directory is
  # `/anji-ext-01/linux-builder`. This host unlocks and mounts both external volumes in
  # `preActivation` at boot, so the volume is ready before the builder's own `preActivation` block
  # runs. The full procedure, with the prerequisite and the verify commands, is in
  # docs/multi-arch-builder.md, "Bootstrapping the Rosetta builder on `anji`".
  legacyLinuxBuilder = false;
  rosettaBuilder = true;
  bootstrapBuilder = false;

  # Store-on-external switch — the cutover flag of `docs/tasks/2026-10/nix-store-external-drive/
  # migration/`. `false`: everything below writes nothing and changes no plist; anji runs its store
  # from the internal volume exactly as before. `true`: every launchd daemon whose payload is a nix
  # binary gets `/usr/local/bin/kdn-nix-bootstrap` as its top-level process (the one binary holding
  # the Full Disk Access grant — see `docs/darwin-quirks.md`), the bootstrap config files land in
  # `/etc/kdn/nix-bootstrap/` as real files, and `darwin-store` mounts `/nix` from the external
  # volume instead of the internal one.
  #
  # The config files must be real files, not `environment.etc` symlinks: the symlinks point into
  # `/nix/store`, and the bootstrap reads them precisely when `/nix/store` is not mounted yet.
  #
  # The Full Disk Access grant on `/usr/local/bin/kdn-nix-bootstrap` is a manual GUI step the owner
  # performs after the binary first lands and before the cutover reboot. Flipping this flag before
  # that grant leaves every nix daemon unable to touch the external volume.
  storeOnExternal = true;

  # The external store volume: `Nix Store Ext`, created 2026-10-13 on the `anji-ext-02` APFS
  # container. It carries no own encryption, so its unlock is the container unlock: `diskutil` on
  # any encrypted volume of a container unlocks every volume of it. The anchor is `anji-ext-02`
  # itself; its System keychain item already exists (see hosts/anji/disks.md).
  storeVolumeUuid = "A8D810B7-5177-4930-890A-10CD1BF7AC96";
  storeUnlockAnchorUuid = "14E59EC3-0C46-4D5C-9CCE-B3D716896F14";

  bootstrapPath = "/usr/local/bin/kdn-nix-bootstrap";

  # Daemons whose nix-darwin `command` is re-homed behind the bootstrap. Socket activation
  # survives the spawn unchanged: launchd resolves a job's `launch_activate_socket` call for
  # every process of that job, so `rosetta-builderd` gets its `Sockets.Listener` from inside the
  # wrapper. Measured 2026-10-15 on macOS 27.0.1: a cache-less x86_64-linux source build ran on
  # the guest through the wrapped builderd. (launchd does NOT pre-place the socket at descriptor
  # 3 for the wrapper — an explicit fd re-pass is both unnecessary and wrong.)
  bootstrapJobs = [
    "nix-daemon"
    "activate-system"
    "sops-install-secrets"
    "rosetta-builderd"
    "angrr"
    "nix-gc"
    "nix-optimise"
    "anji-ext-unlock"
  ];

  bootstrapStoreJson = builtins.toJSON {
    uuid = storeVolumeUuid;
    unlockUuid = storeUnlockAnchorUuid;
    keychainService = storeUnlockAnchorUuid;
    mountPoint = "/nix";
  };

  bootstrapConfigDrv = pkgs.runCommand "kdn-nix-bootstrap-config" { } (
    ''
      mkdir -p "$out/jobs"
      cp ${pkgs.writeText "store.json" bootstrapStoreJson} "$out/store.json"
    ''
    + lib.concatStringsSep "\n" (
      map (name: ''
        cp ${
          pkgs.writeText "${name}.json" (
            builtins.toJSON {
              argv = [
                "/bin/sh"
                "-c"
                (toString config.launchd.daemons."${name}".command)
              ];
              waitPath = "/nix/store";
              env = { };
            }
          )
        } "$out/jobs/${name}.json"
      '') bootstrapJobs
    )
  );

  # Unlock and mount the two external volumes. The passphrases live in the System keychain, one
  # item per volume, keyed by the volume UUID. `diskutil` does not read the keychain itself, so
  # this script reads each passphrase with `security` and pipes it to `diskutil
  # -stdinpassphrase`. `unlockVolume` also mounts, and it is idempotent: a mounted volume is
  # skipped, so a repeated run is safe.
  #
  # Two mechanisms run this script, and both are needed:
  #
  #   - `preActivation` under `lib.mkBefore`. nix-darwin's `nix.linux-builder` writes `mkdir -p
  #     /anji-ext-01/linux-builder` into `preActivation`, and the activation script runs with
  #     `set -e`. An unmounted volume exposes its mount point on the read-only system volume, so
  #     that `mkdir` fails and aborts the whole activation. The unlock must run first.
  #   - a launchd daemon. It re-runs the script after boot, so a volume that appears late, or one
  #     that a user unmounted, comes back without a full activation.
  #
  # See docs/darwin-quirks.md and hosts/anji/disks.md.
  unlockVolumesScript = ''
    for uuid in \
      E630CAE6-D3FB-44C1-9B38-F6211F128B79 \
      14E59EC3-0C46-4D5C-9CCE-B3D716896F14
    do
      if /usr/sbin/diskutil info "$uuid" 2>/dev/null | /usr/bin/grep -q "Mounted:.*Yes"; then
        continue
      fi
      pw="$(/usr/bin/security find-generic-password -s "$uuid" -a "$uuid" -w /Library/Keychains/System.keychain 2>/dev/null)" || {
        echo "anji-ext-unlock: no System keychain item for $uuid" >&2
        continue
      }
      printf "%s" "$pw" | /usr/sbin/diskutil apfs unlockVolume "$uuid" -stdinpassphrase || {
        echo "anji-ext-unlock: unlock failed for $uuid" >&2
        continue
      }
    done
  '';

  slots = kdnConfig.self.mkSlots {
    inherit pkgs;
    # This flake's own host connectivity graph. `pathExists` keeps the import optional, so a tree
    # without the data file still evaluates.
    imports = builtins.filter builtins.pathExists [
      "${kdnConfig.self}/data/slots/slots-ssh-access.nix"
    ];

    kdn.darwin.rosetta-builder.enable = rosettaBuilder;
    # Put the guest disk on the external volume, not on the 256 GB internal disk. The fork input
    # `nazarewk/nix-rosetta-builder` adds the `workingDir` option this needs. No guest exists yet
    # (the phase-2 switch creates the first one), so this relocates nothing and destroys nothing.
    # The volume unlocks in `preActivation` and at boot before the daemon needs it.
    kdn.darwin.rosetta-builder.guest.workingDir = "/anji-ext-01/rosetta-builder";
    # Raise the ceiling from the slot default `150GiB` for the owner's ~200+ GB builds (2026-10-11).
    # The disk is sparse, so the ceiling only bounds growth on the 2 TB external volume.
    kdn.darwin.rosetta-builder.guest.diskSizeMax = "1100GiB";
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
    "${kdnConfig.self}/data/ca/ca-dag.nix"
    {
      imports = kdnConfig.self.denLib.imports {
        class = "darwin";
        aspects = [
          "ca-dag"
          "certificates"
          "ssh-ca"
        ];
      };
    }
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
    (lib.optionalAttrs rosettaBuilder {
      # Rosetta builder guest disk, sized for the owner's ~200+ GB Linux builds (2026-10-11). The
      # guest disk is a sparse file on the external volume (`guest.workingDir`), so a large ceiling
      # costs only what a build actually writes. ⚠️ A change to `diskSize` regenerates `lima.yaml`
      # and recreates the guest; done here on purpose while the guest is a day old.
      #
      # Do NOT set `kdn.darwin.rosetta-builder.guest.minFree` or `.maxFree`. A non-null value
      # regenerates `lima.yaml`, and the daemon then runs `limactl delete --force` on the guest.
      #
      # `optionalAttrs`, not `mkIf`: `mkIf false` still checks the option name against the declared
      # option set, and `nix-rosetta-builder` exists only while its module is imported. So
      # `rosettaBuilder = false` must drop the attribute entirely.
      nix-rosetta-builder.diskSize = "1024GiB";
      # 8 of the M2's 8 cores; 8 GiB of its 16 GiB RAM. The host idles through a build, and the
      # Rosetta VM is the only Linux builder since phase 3 detached the stock one.
      nix-rosetta-builder.cores = 8;
      nix-rosetta-builder.memory = "8GiB";
    })
    {
      system.stateVersion = 6;
      home-manager.sharedModules = [ { home.stateVersion = "26.05"; } ];
    }
    {
      home-manager.sharedModules = [ slots.config.home ];
    }
    {
      # The SSH host certificate. `principals` names the short name (checked by the
      # `kdn-*` dispatcher through `HostKeyAlias`) and each FQDN a client may use.
      kdn.certificates.repoRoot = kdnConfig.self;
      kdn.certificates.certs.ssh-host-anji = {
        ca = "kdn";
        type = "ssh-host";
        commonName = "anji";
        principals = [
          "anji"
          "anji.lan.etra.net.int.kdn.im"
          "anji.priv.nb.net.int.kdn.im"
          "anji.netbird.cloud"
        ];
        directory = "hosts/anji/certs";
        certFile = "ssh_host_ed25519-cert.pub";
        keyFile = "ssh_host_ed25519.key";
        keySource = "managed";
      };
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
      # Unlock and mount the external volumes. `unlockVolumesScript` states why both mechanisms
      # are needed. See docs/darwin-quirks.md and hosts/anji/disks.md.
      system.activationScripts.preActivation.text = lib.mkBefore unlockVolumesScript;

      launchd.daemons.anji-ext-unlock = {
        script = unlockVolumesScript;
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = false;
          StandardOutPath = "/var/log/anji-ext-unlock.log";
          StandardErrorPath = "/var/log/anji-ext-unlock.log";
        };
      };
    }
    (lib.optionalAttrs storeOnExternal {
      # The nix daemons re-homed behind the bootstrap. Each plist's top-level binary becomes the
      # fixed-path bootstrap, and the bootstrap reads the payload (the daemon's own `command`
      # above, captured into a job file) from `/etc/kdn/nix-bootstrap/jobs/<name>.json`. The
      # EnvironmentVariables of each plist stay — the bootstrap passes its own environment on.
      launchd.daemons =
        builtins.listToAttrs (
          map (name: {
            inherit name;
            value = {
              serviceConfig.ProgramArguments = lib.mkForce [
                bootstrapPath
                "run"
                name
              ];
            };
          }) bootstrapJobs
        )
        // {
          # The mount job itself: no payload file, the bootstrap reads `store.json` and unlocks the
          # anchor container before mounting the store volume at `/nix`. This plist was created by
          # the nix installer and regenerated by nothing until now — defining the daemon here takes
          # the label `org.nixos.darwin-store` over, so the RunAtLoad the installer plist carried
          # has to be set explicitly.
          darwin-store = {
            serviceConfig = {
              RunAtLoad = true;
              ProgramArguments = lib.mkForce [
                bootstrapPath
                "mount-store"
              ];
            };
          };
        };

      # Real files at the fixed config dir, plus the binary at its TCC-granted path. `mkAfter` so
      # the volumes are unlocked first, and everything lands before launchd reloads the plists at
      # the end of this same activation. Re-copying the binary on every activation keeps the fixed
      # path current; after a nixpkgs bump that changes the binary, check that the FDA grant
      # survived (docs/darwin-quirks.md: a grant keyed to a path on a replaced binary is the one
      # case that has not been measured).
      system.activationScripts.preActivation.text = lib.mkAfter ''
        mkdir -p /etc/kdn/nix-bootstrap/jobs /usr/local/bin
        cp -f ${bootstrapConfigDrv}/store.json /etc/kdn/nix-bootstrap/store.json
        cp -f ${bootstrapConfigDrv}/jobs/*.json /etc/kdn/nix-bootstrap/jobs/
        cp -f ${pkgs.kdn.kdn-nix-bootstrap}/bin/kdn-nix-bootstrap ${bootstrapPath}
        chmod 0755 ${bootstrapPath}
      '';

      # Fail the evaluation when a wrapped daemon has no command: the swap would then write an
      # empty payload and the job would die at boot.
      assertions = map (name: {
        assertion = config.launchd.daemons."${name}".command != "";
        message = "kdn-nix-bootstrap: launchd.daemons.${name} has no command to wrap";
      }) bootstrapJobs;
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

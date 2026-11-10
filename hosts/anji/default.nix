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

  # Daemons whose nix-darwin `command` is re-homed behind the bootstrap. The wrapper's own comment
  # claimes socket activation survives the spawn (launchd resolves `launch_activate_socket` by the
  # calling process's job, and a spawn counts as the job). That is FALSE for this grandchild
  # process: launchd's top-level process is the wrapper, `limactl hostagent` is its child, and the
  # socket call from the grandchild fails with ESRCH. This is why `rosetta-builderd` sets
  # `onDemand = false` (see the rosettaBuilder block) — that path never calls
  # `launch_activate_socket`. (launchd does NOT pre-place the socket at descriptor 3 for the
  # wrapper — an explicit fd re-pass is both unnecessary and wrong.)
  bootstrapJobs = [
    "nix-daemon"
    "activate-system"
    "sops-install-secrets"
    "rosetta-builderd"
    "angrr"
    "nix-gc"
    "nix-optimise"
    "anji-ext-unlock"
    "kdn-rosetta-farm-forward"
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
    ({ kdn.pkgs.pin = true; })
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

      # Do not upgrade casks/formulae during activation. A `brew bundle` upgrade of the `browsers`
      # cask hung in a sandboxed subprocess on 2026-11-10 (idle ruby stuck in `open()`, no TTY, so
      # no way to answer whatever it waited for) and the activation never completed. Installs still
      # happen on activation; upgrades are a deliberate manual step. `mkForce` because
      # `modules/universal/default.nix` sets the same option to `true` at normal priority.
      homebrew.onActivation.upgrade = lib.mkForce false;
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
      # The image is only the bootstrap. `lima.yaml` then carries a STABLE image path, so a new
      # image does not recreate a running guest, and `guest.system` / `guest.switch` update the
      # guest in place — its disk and `/nix/store` survive. It also removes the yaml's dependency on
      # the aarch64-linux image store path, which a darwin builder cannot accept as an input when
      # the image was built elsewhere and is unsigned (measured 2026-11-10: `rosetta-builder.yaml`
      # failed on anji with "cannot add path … lacks a signature by a trusted key").
      nix-rosetta-builder.mode = "standalone";
      # 8 of the M2's 8 cores; 8 GiB of its 16 GiB RAM. The host idles through a build, and the
      # Rosetta VM is the only Linux builder since phase 3 detached the stock one.
      nix-rosetta-builder.cores = 8;
      nix-rosetta-builder.memory = "8GiB";
      # The build farm's `arm` pool dials this guest DIRECTLY on `anji.lan:31123`
      # (`data/build-farm.nix`, builder `anji-arm`). HAProxy forwards TCP and cannot rewrite the
      # SSH username, so the client authenticates to the guest itself as `kdn-nix-remote-build`.
      # The upstream image is a single-user appliance (`builder` only), so without the account
      # every connection dies at key exchange, the pool marks `anji-arm` down and falls back to the
      # `backup` briv — an SD-card Pi that then runs the aarch64 builds (measured 2026-11-10: the
      # anji build failed on briv `system-path.drv` with the SD card full).
      #
      # Upstream appends this module to the guest's NixOS config, so the account lives in the image.
      # The key is the PUBLIC half of the shared build-farm client key deployed from SOPS as
      # `ssh.kdn-nix-remote-build` (fingerprint SHA256:xtdXqjc/53ZIhTn4bMquc6pGxQvX3gQKpxM7g7MX1P4).
      # Rotate both together. `allowed-users` stays at its `*` default: narrowing it to the new
      # group would lock the guest's own `builder` account out of the daemon. The account IS a
      # `trusted-user` — see the note next to `trusted-users` below for why the usual caveat does
      # not apply to this leaf builder.
      #
      # ⚠️ A new image changes `lima.yaml`, so the daemon deletes and recreates the guest once.
      nix-rosetta-builder.potentiallyInsecureExtraNixosModule = {
        users.groups.kdn-nix-remote-build.gid = 25839;
        users.users.kdn-nix-remote-build = {
          uid = 25839;
          isSystemUser = true;
          group = "kdn-nix-remote-build";
          # `nix-daemon --stdio` runs through the login shell, so the account cannot be `nologin`
          # (sshd then answers "This account is currently not available"). The shell is made
          # unusable for anything but the build protocol by the `Match` block below.
          shell = "/bin/sh";
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID/e1WNc2iAknU+3q/Eh5MAP2oR0rc937aCOCbrtOiSk kdn-nix-remote-build"
          ];
        };

        # The build account must not be a shell account, but the protocol needs a login shell.
        # A `Match` block forces every session of that account to the daemon and removes
        # everything else a shell would give: no TTY, no forwarding, no tunnels.
        #
        # The command is `nix-daemon --stdio`, NOT `nix-store --serve`: the farm's builders are
        # `ssh-ng://` URLs, and an `ssh-ng` client opens the session with `nix-daemon --stdio`.
        # Forcing the legacy `--serve` protocol instead makes every connection die with
        # `protocol mismatch` before a build is dispatched (measured 2026-11-10).
        services.openssh.extraConfig = ''
          Match User kdn-nix-remote-build
            ForceCommand /run/current-system/sw/bin/nix-daemon --stdio
            PermitTTY no
            AllowAgentForwarding no
            AllowTcpForwarding no
            X11Forwarding no
            PermitTunnel no
        '';

        # `nix-daemon --stdio` runs as the connecting account, so that account must be trusted:
        # only trusted users may add unsigned paths, which is what a builder does with every input
        # a client uploads to it and every output it produces.
        #
        # `docs/lix-caveats.md` warns that a trusted client turns the build hook off on the remote
        # host (it switches to `buildDerivation`, which cannot be distributed). That costs nothing
        # HERE: this guest declares no builders of its own, so there is nothing for it to forward.
        # The caveat applies to `anji` as a builder for other hosts, not to this leaf.
        #
        # Shell access stays with `builder` (the host key, passwordless sudo for in-place updates),
        # which is the management account.
        nix.settings.trusted-users = [ "kdn-nix-remote-build" ];

        # 8 GiB RAM is not enough for every aarch64 build. `rustc` compiling atuin's test harness
        # was killed by the OOM killer twice (measured 2026-11-10, `anon-rss` 2.4 GB with several
        # rustc processes alive, `--cores 2` did not save it). The guest's disk is a sparse 1 TiB
        # image on the external volume, so an 8 GiB swap file is cheap and keeps the build alive
        # without touching `nix-rosetta-builder.memory` — that option feeds `lima.yaml`, and
        # changing it deletes the guest together with its store.
        swapDevices = [
          {
            device = "/var/swapfile";
            size = 8192;
          }
        ];

        # The farm's HAProxy health check opens a connection every 10 s and closes it before
        # authenticating. OpenSSH 10 counts exactly that as a penalty trigger, so the guest kept
        # resetting the checks (`ECONNRESET … at step 1 of tcp-check`) and the `anji-arm` backend
        # stayed DOWN. Exempt the guest's own lima network, which is the only path the checks and
        # the host take; the public-facing penalty logic is irrelevant for this appliance.
        services.openssh.settings.PerSourcePenaltyExemptList = "192.168.5.0/24";
      };
      # builderd's launchd PATH must start with /usr/bin. The fork's module (module.nix:307-326)
      # builds the job PATH without it, so lima's guest bootstrap execs the nix openssh from PATH;
      # nixpkgs builds openssh without GSSAPI, and lima passes `-o GSSAPIAuthentication=no`, which
      # that build rejects as an unsupported option — the guest provisioning ssh then dies and the
      # VM never becomes reachable (measured 2026-10-17 on macOS 27.0.1; live plist edit with this
      # same prefix fixed it: Apple ssh 10.3.1 parses the option and the guest booted + served
      # sshd). `mkBefore` prepends to the fork's list; the fork should carry /usr/bin upstream.
      launchd.daemons.rosetta-builderd.path = lib.mkBefore [ "/usr/bin" ];
      # Disable socket activation. The daemon is re-homed behind `kdn-nix-bootstrap`
      # (`bootstrapJobs` above) for the Full Disk Access grant, so launchd's top-level process is
      # the wrapper and `limactl hostagent` is a *grandchild*. On the onDemand path lima calls
      # `launch_activate_socket("Listener")` from that grandchild; the call resolves the socket by
      # the calling process's launchd job, the grandchild has a different bootstrap, and the call
      # fails with ESRCH ("no such process"). The hostagent then exits ~19 s into every start
      # (`ha.stderr.log`: `Driver stopped due to error: "launchd socket \"Listener\" failed to
      # activate: no such process"`), launchd respawns it, and the VZ guest is torn down and
      # rebooted before it can finish booting — the guest sshd never becomes reachable (measured
      # 2026-10-17; runs=132, one cycle per ~19 s). The wrapper comment that claims socket
      # activation survives was measured on the non-onDemand path, where `forwardLaunchdToSSH` is
      # never taken. `onDemand = false` drops `Sockets.Listener` from the plist entirely and sets
      # `KeepAlive = true`, so the daemon keeps the VM resident and lima uses plain SSH forwarding
      # on `port` (module.nix:393-399, module.nix:246). The trade-off: the guest no longer powers
      # off when idle, which is right for a build host. NOTE: this changes the generated
      # `lima.yaml` (`ssh.launchdSocketName`), so the next daemon start recreates the guest once.
      nix-rosetta-builder.onDemand = false;
      # The fork sets `Sockets."Listener" = optionalAttrs cfg.onDemand {...}`. With
      # `onDemand = false` that is `{}`, but the key still renders — an empty `<dict/>` inside
      # `<key>Sockets</key>`. launchd would then register an empty socket. Clear it so the plist
      # carries no `Sockets` block at all. (A fork fix should drop the key, not empty it.)
      launchd.daemons.rosetta-builderd.serviceConfig.Sockets = lib.mkForce { };
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
    }
    {
      # anji's aarch64-linux builds land in the Linux builder VM, not this darwin host, so trusting
      # the build-farm clients' signing keys here (on the darwin side) would only widen the darwin
      # host's trust for nothing. The VM gets it via anji/linux-builder.nix instead.
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

      # Expose the Rosetta builder VM's sshd (host-local 127.0.0.1:31122) on the LAN, so the build
      # farm's `arm` pool reaches the aarch64-linux VM DIRECTLY and never touches this darwin host
      # (which cannot build the kernel-source FOD — docs/lix-caveats.md). The build-farm `anji-arm`
      # builder dials anji.lan:31123. See docs/tasks/2026-11/rosetta-vm-farm-builder/.
      launchd.daemons.kdn-rosetta-farm-forward = {
        command = "${pkgs.socat}/bin/socat TCP-LISTEN:31123,reuseaddr,fork TCP:127.0.0.1:31122";
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "/var/log/kdn-rosetta-farm-forward.log";
          StandardErrorPath = "/var/log/kdn-rosetta-farm-forward.log";
        };
      };

      # The macOS application firewall decides per BINARY, and socat has no allowance by default:
      # a LAN connection to 31123 is dropped before it reaches socat, while a loopback connection
      # bypasses the firewall and works — so the forward looks healthy on the host and dead from
      # everywhere else (measured 2026-11-10: HAProxy kept `anji-arm` DOWN with ECONNRESET).
      # The allowance names a store path, so every nixpkgs bump revokes it silently; no nix-darwin
      # option covers per-app entries, so re-add it on activation. See hosts/anji/bootstrap.md.
      system.activationScripts.anji-firewall.text = ''
        alf=/usr/libexec/ApplicationFirewall/socketfilterfw
        if ! "$alf" --listapps 2>/dev/null | grep -Fq -- '${pkgs.socat}'; then
          "$alf" --add '${pkgs.socat}/bin/socat' >/dev/null 2>&1 || true
          "$alf" --unblockapp '${pkgs.socat}/bin/socat' >/dev/null 2>&1 || true
          echo "anji: allowed socat through the application firewall (farm forward on 31123)" >&2
        fi
      '';
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

      # Real files at the fixed config dir, plus the binary at its TCC-granted path — installed
      # ONCE and never replaced in place. `mkAfter` so the volumes are unlocked first, and
      # everything lands before launchd reloads the plists at the end of this same activation.
      #
      # Two measured TCC facts (docs/darwin-quirks.md) make replacement hostile, both seen
      # 2026-10-15 on macOS 27.0.1: (1) the grant binds the binary's cdhash — writing different
      # bytes at the granted path flips the entry to DENIED (auth_value 0) for the whole tree,
      # until the owner re-grants in the GUI; (2) `cp -f` truncates the vnode a running job is
      # executing from, tainting it so even the ORIGINAL bytes SIGKILL at exec ("rejecting
      # invalid page ... tainted"). So: create-if-missing only. Rotating the bootstrap is an
      # explicit, owner-coordinated move: `rm /usr/local/bin/kdn-nix-bootstrap`, activate, re-grant.
      system.activationScripts.preActivation.text = lib.mkAfter ''
        mkdir -p /etc/kdn/nix-bootstrap/jobs /usr/local/bin
        cp -f ${bootstrapConfigDrv}/store.json /etc/kdn/nix-bootstrap/store.json
        cp -f ${bootstrapConfigDrv}/jobs/*.json /etc/kdn/nix-bootstrap/jobs/
        if [ ! -e ${bootstrapPath} ]; then
          cp ${pkgs.kdn.kdn-nix-bootstrap}/bin/kdn-nix-bootstrap ${bootstrapPath}.new
          chmod 0755 ${bootstrapPath}.new
          mv -f ${bootstrapPath}.new ${bootstrapPath}
          echo "anji: kdn-nix-bootstrap installed — it needs a Full Disk Access grant before the next activation of a store-on-external config" >&2
        fi
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

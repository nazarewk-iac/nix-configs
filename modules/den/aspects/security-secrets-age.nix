# The `security/secrets/age` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It gives sops an age key on every machine. Three parts do that:
#
# 1. A **generator set**. `kdn.security.secrets.age.genScripts` collects one script per key source.
#    The option `apply` folds the list into a single command, `kdn-sops-age-gen-keys`. It prints
#    every private key it finds, one per line. The default entry converts the host SSH key.
# 2. A **service pre-start**. On NixOS the `sops-install-secrets` unit runs the generator first and
#    merges the result into the key file. On Darwin the post-activation script does the same.
# 3. A **`sops` wrapper**. An overlay wraps the `sops` command, so an interactive edit gets the same
#    keys through `SOPS_AGE_KEY`. `KDN_SOPS_AGE_GEN_KEYS=0` turns that off.
#
# The `hw-yubikey` aspect writes into both `plugins` and `genScripts`, so a YubiKey key joins the
# same set with no change here.
#
# ## One declaration, three classes
#
# The options live in the two `declaration` modules below, and each target imports one of them. Only
# one class loads per evaluation, so the module system sees exactly one declaration each time.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch. The old default follows
#    `kdn.security.secrets.enable`, and den has no such flag.
# 2. **`kdn.env.packages` goes.** Each target writes the native package option of its own class,
#    through ../common/filter-packages.nix. Design B.
# 3. **The aspect imports the sops-nix module itself,** for the two host classes. The old tree
#    imports it for every host. Precedent: ./disks.nix:206-207.
# 4. **The key file path becomes an option.** The old module writes `sops.age.keyFile` and then
#    reads the same option back for the pre-start script. This aspect holds one option,
#    `kdn.security.secrets.age.keyFile`, writes it into `sops.age.keyFile`, and reads only its own
#    value. The default keeps the old path, so behaviour does not change. The read-back also fails
#    in the `homeManager` class, where nothing declares `sops.age.keyFile`.
# 5. **The `homeManager` class carries the packages alone.** The old module's Home Manager half
#    writes no sops option either, so this aspect imports no Home Manager sops module.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module takes `config`, `lib` and `pkgs` only.
#    `inputs` comes from this file's own scope, because the check harness passes `pkgs` alone to a
#    target.
{ inputs, ... }:
let
  # The options every class needs.
  declaration =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.security.secrets.age;
    in
    {
      options.kdn.security.secrets.age.plugins = lib.mkOption {
        type = with lib.types; listOf package;
        default = [ ];
        description = ''
          age plugin packages. Every plugin reaches the `sops` wrapper and the
          `sops-install-secrets` unit, so a hardware key works in both places.
        '';
      };

      options.kdn.security.secrets.age.tpm = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Seed a TPM-backed age identity into the key file, so the boot-time decrypt needs no
            YubiKey, no smart card and no interactive touch.

            `age-plugin-tpm` derives a key from the host's TPM 2.0 and stores a wrapped blob in
            `identityFile`. The blob is a plain file, so it must live on a persistent path: the TPM
            itself survives a reinstall, the blob does not unless it is kept. Back it up off-host,
            and never run `tpm2_clear` on an enrolled machine, because that destroys the owner
            hierarchy that unwraps the blob.

            There is no PCR binding in `age-plugin-tpm` 1.0.1, so a firmware or kernel update does
            not break decryption. That is also why this protects against a stolen disk, not against
            an attacker at the console; full disk encryption is the control for that case.

            Enrolment is a one-time interactive step per host; see
            `docs/tasks/2026-10/tpm-age-sops-keys/`.
          '';
        };
        waitSeconds = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 0;
          example = 30;
          description = ''
          Wait up to this many seconds for a USABLE TPM before the decrypt, and then continue
          regardless. The TPM is busy early in boot (cryptsetup unseals the LUKS volumes and
          libvirtd opens a TPM secret in the same seconds), and the resource manager then answers
          `Esys_Load` with a TPM error. On 2026-11-04 that made the boot-time decrypt fail, so
          `kdn-secrets.target` was never reached and sshd failed its dependency.

          `0` disables the wait. The probe is opt-in per host: it costs up to this many seconds of
          boot, and most hosts do not need it because their SSH host key is already a recipient.
                  '';
        };
        identityFile = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/sops-tpm/tpm-identity.txt";
          example = "/var/lib/sops-tpm/tpm-identity.txt";
          description = ''
            The on-disk `AGE-PLUGIN-TPM-…` identity blob. It must be a persistent path and must be
            readable only by root. The pre-start script copies it into the merged key file.
          '';
        };
      };

      options.kdn.security.secrets.age.keyFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/sops-nix/key.txt";
        example = "/var/lib/my-keys/age.txt";
        description = ''
          Where the merged age key file lives. The two host classes write this value into
          `sops.age.keyFile`, and the pre-start script below merges every generated key into it.
        '';
      };

      options.kdn.security.secrets.age.genScripts = lib.mkOption {
        type = with lib.types; listOf package;
        default = [ ];
        description = ''
          One script per key source. Each script prints zero or more age private keys on standard
          output, and it prints nothing when its source is absent.

          The `apply` below folds the whole list into a single package,
          `kdn-sops-age-gen-keys`. So this option **reads** as one package, not as a list.
          `passthru.scripts` keeps the original list.
        '';
        apply =
          packages:
          lib.pipe packages [
            (map lib.getExe)
            (builtins.concatStringsSep "\n")
            (
              text:
              pkgs.writeShellApplication {
                name = "kdn-sops-age-gen-keys";
                derivationArgs.passthru.scripts = packages;
                runtimeInputs = with pkgs; [
                  coreutils
                ];

                text = ''
                  output="''${1:-"-"}"
                  if test "$output" == "-" ; then
                    output="/dev/stdout"
                  else
                    outdir="''${output%/*}"
                    test "$outdir" == "$output" || mkdir -p "$outdir"
                  fi
                  # BEST-EFFORT per source. A key source that is merely UNAVAILABLE must not
                  # abort the others. The YubiKey generator errors when `pcscd` is not yet up at
                  # boot ("PC/SC error: Access was denied"), and with `set -e` that killed the
                  # whole subshell — so the SSH host-key identity was never written, `sops`
                  # found no working key, `sops-install-secrets` failed, `kdn-secrets.target`
                  # failed, and sshd's dependency took SSH down with it (oams, 2026-11-05; the
                  # same class as the brys incident of 2026-11-04). Each source is now
                  # independent: it contributes its keys if it can, and is skipped otherwise.
                  {
                    while IFS= read -r _kdn_gen_script; do
                      [ -n "$_kdn_gen_script" ] || continue
                      "$_kdn_gen_script" || true
                    done <<'__KDN_GEN_SCRIPTS__'
${text}
__KDN_GEN_SCRIPTS__
                  } >"$output"
                '';
              }
            )
          ];
      };

      config.kdn.security.secrets.age.genScripts = [
        (lib.mkIf cfg.tpm.enable (
          pkgs.writeShellApplication {
            name = "kdn-sops-age-gen-keys-tpm";
            runtimeInputs = with pkgs; [
              coreutils
              age-plugin-tpm
            ];
            text = ''
              # The blob is the whole identity for `age-plugin-tpm`; it prints nothing when the
              # file is absent, so a host without an enrolled TPM is unaffected.
              if test -r ${lib.strings.escapeShellArg cfg.tpm.identityFile}; then
                cat ${lib.strings.escapeShellArg cfg.tpm.identityFile}
              fi
            '';
          }
        ))
        (pkgs.writeShellApplication {
          name = "kdn-sops-age-gen-keys-ssh";
          runtimeInputs = with pkgs; [
            coreutils
            ssh-to-age
          ];
          text = ''
            # -r FILE   Returns true if FILE is marked as readable.
            if test -r /etc/ssh/ssh_host_ed25519_key; then
              ssh-to-age -i /etc/ssh/ssh_host_ed25519_key -private-key
            fi
          '';
        })
      ];

      # `lib.strings.escapeShellArg` guards the path, and the plain interpolations follow the old
      # module. The script creates the parent directory, then merges the generated keys in.
      options.kdn.security.secrets.age.service.preStart = lib.mkOption {
        type = with lib.types; package;
        default = pkgs.writeShellApplication {
          name = "kdn-sops-pre-start";
          runtimeInputs = with pkgs; [
            coreutils
          ];

          text = ''
            keyFile=${lib.strings.escapeShellArg cfg.keyFile}
            mkdir -p "''${keyFile%/*}"
            test -e "$keyFile" || touch "$keyFile"
            {
              cat ${cfg.keyFile}
              ${lib.getExe cfg.genScripts}
            } | sort -u >${cfg.keyFile}.tmp
            mv ${cfg.keyFile}.tmp ${cfg.keyFile}
          '';
        };
        defaultText = lib.literalMD "a script that merges every generated key into `keyFile`";
        description = ''
          The command that runs before `sops-install-secrets` on NixOS, and inside the
          post-activation script on Darwin.
        '';
      };
    };

  # Every package this aspect ships, in every class.
  packagesOf =
    {
      config,
      lib,
      pkgs,
    }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    filterPackages (
      with pkgs;
      [
        age
        ssh-to-age
        ssh-to-pgp
        config.kdn.security.secrets.age.genScripts
      ]
    );

  # The `sops` command, wrapped so an interactive edit sees every generated key.
  #
  # The wrapper builds from `prev`, the package set before this overlay, so it cannot recurse into
  # itself. `buildEnv` keeps the original package on the path for every other output.
  mkSopsWrapper =
    { config, lib }:
    prev: pkg:
    let
      cfg = config.kdn.security.secrets.age;
      baseName = pkg.meta.mainProgram or pkg.pname or pkg.name;
      script = prev.writeShellApplication {
        name = baseName;
        runtimeInputs =
          with prev;
          [
            gnused
            age
          ]
          ++ cfg.plugins;
        inherit (pkg) meta passthru;
        text = ''
          if test "''${KDN_SOPS_AGE_GEN_KEYS:-"1"}" == 1 ; then
            SOPS_AGE_KEY="$(
              {
                echo "''${SOPS_AGE_KEY:-""}"
                ${lib.getExe cfg.genScripts} 2>/dev/null
              } | sed '/^$/d'
            )"
          fi
          export SOPS_AGE_KEY
          ${lib.getExe pkg} "$@"
        '';
      };
    in
    prev.buildEnv {
      name = "${baseName}-${pkg.version}-sops-age-wrapped";
      paths = [
        (lib.hiPrio script)
        pkg
      ];
    };

  # What both host classes share: the sops-nix key settings and the `sops` wrapper overlay.
  hostShared =
    { config, lib, pkgs, ... }:
    {
      # Fake the file presence, or the install fails. See
      # https://github.com/Mic92/sops-nix/issues/65 . sops-nix imports the SSH key on its own.
      sops.gnupg.sshKeyPaths = [ ];
      sops.age.sshKeyPaths = [ ];
      sops.age.generateKey = false;
      sops.age.keyFile = config.kdn.security.secrets.age.keyFile;

    };

  nixosTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        declaration
        hostShared
        inputs.sops-nix.nixosModules.sops
      ];

      environment.systemPackages = packagesOf { inherit config lib pkgs; };

      systemd.services.sops-install-secrets.path =
        config.kdn.security.secrets.age.plugins
        ++ lib.optionals config.kdn.security.secrets.age.tpm.enable [ pkgs.age-plugin-tpm ];
      systemd.services.sops-install-secrets.preStart = lib.getExe config.kdn.security.secrets.age.service.preStart;

      # A TPM identity needs the device and the module, or the decrypt races the driver.
      security.tpm2.enable = lib.mkDefault config.kdn.security.secrets.age.tpm.enable;

      # The TPM is BUSY early in boot, not missing: cryptsetup unseals the LUKS volumes and
      # libvirtd opens a TPM secret in the same seconds, and the resource manager then answers
      # `Esys_Load` with a TPM error ("No locks available"). On 2026-11-04 that cost brys its
      # sshd: sops-install-secrets failed, kdn-secrets.target was never reached, and sshd
      # (Requires=kdn-secrets.target) failed its dependency.
      #
      # So: order after the encrypted volumes, wait up to 30 s for a usable TPM, then continue
      # ANYWAY (exit 0). Continuing is deliberate — the SSH host key identity decrypts, and
      # blocking here would repeat the lockout. `Restart=on-failure` is the second net.
      # NO `pcscd.service` or `cryptsetup.target` edge here: `pcscd` pulls in `basic.target`,
      # `sockets.target`, `cups.socket` and `sysinit.target`, which closes a cycle back through
      # sops. systemd then DELETES this job, sshd (Requires=kdn-secrets.target, BindsTo this
      # service) goes with it, and the host is reachable only over the KVM. Measured twice:
      # 2026-10-27/28 in the old tree, and 2026-11-04 with this edge added. The ordering is
      # already safe: `dev-tpmrm0.device` and `RequiresMountsFor` cover the real dependencies.
      systemd.services.sops-install-secrets.after =
        lib.optional config.kdn.security.secrets.age.tpm.enable "dev-tpmrm0.device";
      systemd.services.sops-install-secrets.wants =
        lib.optional config.kdn.security.secrets.age.tpm.enable "dev-tpmrm0.device";
      systemd.services.sops-install-secrets.serviceConfig = {
        Restart = lib.mkDefault "on-failure";
        RestartSec = lib.mkDefault 5;
        ExecStartPre = lib.optional (config.kdn.security.secrets.age.tpm.enable && config.kdn.security.secrets.age.tpm.waitSeconds > 0) (
          pkgs.writeShellScript "kdn-sops-wait-tpm" ''
            if [ ! -e /dev/tpmrm0 ]; then exit 0; fi
            deadline=$(( $(date +%s) + ${toString config.kdn.security.secrets.age.tpm.waitSeconds} ))
            while [ "$(date +%s)" -lt "$deadline" ]; do
              if ${pkgs.tpm2-tools}/bin/tpm2_getrandom 1 >/dev/null 2>&1; then exit 0; fi
              sleep 2
            done
            echo "kdn-sops-wait-tpm: TPM still busy after ${toString config.kdn.security.secrets.age.tpm.waitSeconds} s; continuing with the other identities" >&2
            exit 0
          ''
        );
      };
      systemd.services.sops-install-secrets.unitConfig.StartLimitIntervalSec = lib.mkDefault 0;

      # The identity blob sits on a persistent path (`/var/lib/sops-tpm`, a bind mount from
      # the ZFS state bucket). Without this, the unit starts before that mount exists: the
      # generator's `test -r` then prints nothing, the merged key file has no TPM identity,
      # and the decrypt fails — sshd never starts. `RequiresMountsFor` makes systemd order
      # and require the mount units covering the path, which is the only reliable way: the
      # mount's unit name is derived from the path and is not stable across layouts.
      systemd.services.sops-install-secrets.unitConfig.RequiresMountsFor =
        lib.optional config.kdn.security.secrets.age.tpm.enable config.kdn.security.secrets.age.tpm.identityFile;
    };

  darwinTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        declaration
        hostShared
        inputs.sops-nix.darwinModules.default
      ];

      environment.systemPackages = packagesOf { inherit config lib pkgs; };

      system.activationScripts.postActivation.text = lib.mkBefore (
        lib.getExe config.kdn.security.secrets.age.service.preStart
      );
    };

  homeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      home.packages = packagesOf { inherit config lib pkgs; };
    };
in
{
  # No `includes` entry. The old module reads no option of the `secrets` aspect, and it gates
  # nothing on `kdn.security.secrets.allow`. A host that wants both aspects names both.
  kdn.security-secrets-age.nixos = nixosTarget;
  kdn.security-secrets-age.darwin = darwinTarget;
  kdn.security-secrets-age.homeManager = homeTarget;
}

{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.security.secrets.age;

  mkSopsWrapper =
    pkgs: pkg:
    let
      baseName = pkg.meta.mainProgram or pkg.pname or pkg.name;
      script = pkgs.writeShellApplication {
        name = baseName;
        runtimeInputs =
          with pkgs;
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
    pkgs.buildEnv {
      name = "${baseName}-${pkg.version}-sops-age-wrapped";
      paths = [
        (lib.hiPrio script)
        pkg
      ];
    };
in
{
  options.kdn.security.secrets.age = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = config.kdn.security.secrets.enable;
    };
    plugins = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
    };
    tpm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Seed a TPM 2.0-backed age identity into the key file, so the boot-time decrypt needs no
          YubiKey, no smart card and no interactive touch.

          `age-plugin-tpm` derives a key from the host TPM and keeps a wrapped blob in
          `identityFile`. The blob is a plain file, so it must live on a persistent path; the TPM
          survives a reinstall but the blob does not unless it is kept. Back it up off-host and
          never `tpm2_clear` on an enrolled machine.

          There is no PCR binding in `age-plugin-tpm` 1.0.1, so firmware and kernel updates do not
          break decryption. That is also why it protects a stolen disk, not a live attacker; full
          disk encryption is the control for that.
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
        description = ''
          The on-disk `AGE-PLUGIN-TPM-…` blob, readable only by root. Enrolment is a one-time
          interactive step; see `docs/tasks/2026-10/tpm-age-sops-keys/`.
        '';
      };
    };
    genScripts = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
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
                                # BEST-EFFORT per source. A source that is merely UNAVAILABLE must not abort
                                # the others. At boot the YubiKey generator errors while pcscd is still coming
                                # up ("PC/SC error: Access was denied"); with `set -e` that killed the whole
                                # subshell, the SSH host-key identity was never captured, the pre-start
                                # pipeline failed, `mv` never ran, and key.txt kept no usable key — so
                                # sops-install-secrets failed and sshd's dependency took SSH down (oams
                                # 2026-11-05; same class as brys 2026-11-04). Each source now runs on its own
                                # and is skipped if it fails.
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
    service.preStart = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.writeShellApplication {
        name = "kdn-sops-pre-start";
        runtimeInputs = with pkgs; [
          coreutils
        ];

        text = ''
          keyFile=${lib.strings.escapeShellArg config.sops.age.keyFile}
          mkdir -p "''${keyFile%/*}"
          test -e "$keyFile" || touch "$keyFile"
          {
            cat ${config.sops.age.keyFile}
            ${lib.getExe cfg.genScripts}
          } | sort -u >${config.sops.age.keyFile}.tmp
          mv ${config.sops.age.keyFile}.tmp ${config.sops.age.keyFile}
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          age
          ssh-to-age
          ssh-to-pgp
          cfg.genScripts
        ];
        kdn.security.secrets.age.plugins = lib.optionals cfg.tpm.enable [ pkgs.age-plugin-tpm ];
        kdn.security.secrets.age.genScripts = [
          (lib.mkIf cfg.tpm.enable (
            pkgs.writeShellApplication {
              name = "kdn-sops-age-gen-keys-tpm";
              runtimeInputs = with pkgs; [
                coreutils
              ];
              text = ''
                # The blob is the whole identity; nothing is printed when it is absent, so a host
                # without an enrolled TPM is unaffected.
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
      }
      (kdnConfig.util.ifTypes [ "nixos" "darwin" ] (
        lib.mkMerge [
          # modules that are supported by sops-nix
          # TODO: home-manager module
          {
            # fake the file presence, otherwise the install fails
            # see https://github.com/Mic92/sops-nix/issues/65
            # note: SSH key gets imported automatically
            sops.gnupg.sshKeyPaths = [ ];
            sops.age.sshKeyPaths = [ ];
            sops.age.generateKey = false;
            sops.age.keyFile = "/var/lib/sops-nix/key.txt";

          }
        ]
      ))
      (kdnConfig.util.ifTypes [ "nixos" ] (
        lib.mkMerge [
          {
            systemd.services.sops-install-secrets.path = cfg.plugins;
            systemd.services.sops-install-secrets.preStart = lib.getExe cfg.service.preStart;
            # A TPM identity reads /dev/tpmrm0, so the device must exist before the decrypt runs.
            security.tpm2.enable = lib.mkDefault cfg.tpm.enable;
            # The TPM is BUSY early in boot, not missing: cryptsetup unseals the LUKS volumes and
            # libvirtd opens a TPM secret in the same seconds, and the resource manager then
            # answers Esys_Load with a TPM error. On 2026-11-04 that cost brys its sshd:
            # sops-install-secrets failed, kdn-secrets.target was never reached, and sshd
            # (Requires=kdn-secrets.target) failed its dependency.
            #
            # Order after the encrypted volumes, wait up to 30 s for a usable TPM, then continue
            # ANYWAY (exit 0): the SSH host key identity decrypts, and blocking would repeat the
            # lockout. Restart=on-failure is the second net.
            # NO `pcscd.service` or `cryptsetup.target` edge here: `pcscd` pulls in `basic.target`,
            # `sockets.target`, `cups.socket` and `sysinit.target`, which closes a cycle back through
            # sops. systemd then DELETES this job, sshd (Requires=kdn-secrets.target, BindsTo this
            # service) goes with it, and the host is reachable only over the KVM. Measured twice:
            # 2026-10-27/28 in the old tree, and 2026-11-04 with this edge added. The ordering is
            # already safe: `dev-tpmrm0.device` and `RequiresMountsFor` cover the real dependencies.
            systemd.services.sops-install-secrets.after = lib.optional cfg.tpm.enable "dev-tpmrm0.device";
            systemd.services.sops-install-secrets.wants = lib.optional cfg.tpm.enable "dev-tpmrm0.device";
            systemd.services.sops-install-secrets.serviceConfig = {
              Restart = lib.mkDefault "on-failure";
              RestartSec = lib.mkDefault 5;
              ExecStartPre = lib.optional (cfg.tpm.enable && cfg.tpm.waitSeconds > 0) (
                pkgs.writeShellScript "kdn-sops-wait-tpm" ''
                  if [ ! -e /dev/tpmrm0 ]; then exit 0; fi
                  deadline=$(( $(date +%s) + ${toString cfg.tpm.waitSeconds} ))
                  while [ "$(date +%s)" -lt "$deadline" ]; do
                    if ${pkgs.tpm2-tools}/bin/tpm2_getrandom 1 >/dev/null 2>&1; then exit 0; fi
                    sleep 2
                  done
                  echo "kdn-sops-wait-tpm: TPM still busy after ${toString cfg.tpm.waitSeconds} s; continuing with the other identities" >&2
                  exit 0
                ''
              );
            };
            systemd.services.sops-install-secrets.unitConfig.StartLimitIntervalSec = lib.mkDefault 0;
            # The blob lives on a persistent bind mount. Order and require its mount unit,
            # or the unit starts first, the generator prints nothing, and the decrypt fails.
            systemd.services.sops-install-secrets.unitConfig.RequiresMountsFor =
              lib.optional cfg.tpm.enable cfg.tpm.identityFile;
          }
        ]
      ))
      (kdnConfig.util.ifTypes [ "darwin" ] (
        lib.mkMerge [
          {
            system.activationScripts.postActivation.text = lib.mkBefore (lib.getExe cfg.service.preStart);
          }
        ]
      ))
    ]
  );
}

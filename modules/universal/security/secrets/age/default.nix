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
      identityFile = lib.mkOption {
        type = lib.types.str;
        default = "/persist/sops/tpm-identity.txt";
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
                ( ${text} ) >"$output"
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
        kdn.security.secrets.age.plugins =
          lib.optionals cfg.tpm.enable [ pkgs.age-plugin-tpm ];
        kdn.security.secrets.age.genScripts = [
          (lib.mkIf cfg.tpm.enable (pkgs.writeShellApplication {
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
          }))
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

            nixpkgs.overlays = [
              (lib.mkAfter (
                final: prev: {
                  sops = mkSopsWrapper prev prev.sops;
                }
              ))
            ];
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
            systemd.services.sops-install-secrets.after = lib.optional cfg.tpm.enable "dev-tpmrm0.device";
            systemd.services.sops-install-secrets.wants = lib.optional cfg.tpm.enable "dev-tpmrm0.device";
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

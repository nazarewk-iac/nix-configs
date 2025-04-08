{
  lib,
  pkgs,
  config,
  kdn,
  ...
}: let
  inherit (kdn) inputs;

  cfg = config.kdn.security.secrets.age;

  mkSopsWrapper = pkgs: pkg: let
    baseName = pkg.meta.mainProgram or pkg.pname or pkg.name;
    script = pkgs.writeShellApplication {
      name = baseName;
      runtimeInputs = with pkgs;
        [
          gnused
          age
        ]
        ++ config.sops.age.plugins;
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
in {
  options.kdn.security.secrets.age = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = config.kdn.security.secrets.enable;
    };
    genScripts = lib.mkOption {
      type = with lib.types; listOf package;
      default = [];
      apply = packages:
        lib.pipe packages [
          (builtins.map lib.getExe)
          (builtins.concatStringsSep "\n")
          (text:
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
            })
        ];
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      nixpkgs.overlays = [
        (lib.mkAfter (final: prev: {
          sops = mkSopsWrapper prev prev.sops;
        }))
      ];

      environment.systemPackages = with pkgs; [
        age
        ssh-to-age
        ssh-to-pgp
        cfg.genScripts
      ];

      kdn.security.secrets.age.genScripts = [
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
    {
      # fix for https://github.com/Mic92/sops-nix/pull/680#issuecomment-2580744439
      # see https://github.com/NixOS/nixpkgs/blob/b33acd9911f90eca3f2b11a0904a4205558aad5b/nixos/lib/systemd-lib.nix#L473-L473
      systemd.services.sops-install-secrets.environment.PATH = let
        path = config.systemd.services.sops-install-secrets.path;
      in
        lib.mkForce "${lib.makeBinPath path}:${lib.makeSearchPathOutput "bin" "sbin" path}";
      systemd.services.sops-install-secrets.path = config.sops.age.plugins;
    }
    {
      # fake the file presence, otherwise the install fails
      # see https://github.com/Mic92/sops-nix/issues/65
      # note: SSH key gets imported automatically
      sops.gnupg.sshKeyPaths = [];
      sops.age.sshKeyPaths = [];
      sops.age.generateKey = false;
      sops.age.keyFile = "/var/lib/sops-nix/key.txt";
      systemd.services.sops-install-secrets.path = with pkgs; [coreutils];
      systemd.services.sops-install-secrets.preStart = ''
        keyFile=${lib.strings.escapeShellArg config.sops.age.keyFile}
        mkdir -p "''${keyFile%/*}"
        test -e "$keyFile" || touch "$keyFile"
        {
          cat ${config.sops.age.keyFile}
          ${lib.getExe cfg.genScripts}
        } | sort -u >${config.sops.age.keyFile}.tmp
        mv ${config.sops.age.keyFile}.tmp ${config.sops.age.keyFile}
      '';
    }
  ]);
}

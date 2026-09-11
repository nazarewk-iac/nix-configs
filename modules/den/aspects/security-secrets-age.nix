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
                  ( ${text} ) >"$output"
                '';
              }
            )
          ];
      };

      config.kdn.security.secrets.age.genScripts = [
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
    { config, lib, ... }:
    {
      # Fake the file presence, or the install fails. See
      # https://github.com/Mic92/sops-nix/issues/65 . sops-nix imports the SSH key on its own.
      sops.gnupg.sshKeyPaths = [ ];
      sops.age.sshKeyPaths = [ ];
      sops.age.generateKey = false;
      sops.age.keyFile = config.kdn.security.secrets.age.keyFile;

      nixpkgs.overlays = [
        (lib.mkAfter (
          _final: prev: {
            sops = mkSopsWrapper { inherit config lib; } prev prev.sops;
          }
        ))
      ];
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

      systemd.services.sops-install-secrets.path = config.kdn.security.secrets.age.plugins;
      systemd.services.sops-install-secrets.preStart = lib.getExe config.kdn.security.secrets.age.service.preStart;
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

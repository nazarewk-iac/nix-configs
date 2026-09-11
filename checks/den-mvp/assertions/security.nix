# Tier-1 assertions for the four `security-*` aspects.
#
# Every assertion is `{ name; expected; actual; }`, and `mkEvalCheck` compares the two at evaluation
# time. Nothing here activates.
#
# ## The subjects
#
# | Subject | Class | What it states |
# |---|---|---|
# | `nixosSecrets` | `nixos` | disk encryption, age and sops together, with userborn on |
# | `nixosSecureBoot` | `nixos` | the lanzaboote aspect, read as values |
# | `darwinSecrets` | `darwin` | the two aspects that emit a `darwin` target |
# | `homeAge` | `homeManager` | the one aspect that emits a `homeManager` target |
#
# ## Why `services.userborn.enable` is on
#
# The sops aspect asserts `services.userborn.enable || services.sysusers.enable`. The old module
# holds the same assertion, so the subject states the fact instead of a weaker aspect.
#
# ## Why `nixosSecureBoot` reads values and forces no `drvPath`
#
# lanzaboote replaces the whole boot loader, and a force would build the signed-boot machinery for no
# gain. `den-eval-instantiate` already forces every registry pair, so the target module body gets its
# coverage there. This subject reads the three option values that the port must preserve.
{
  lib,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos bareDarwinSystem bareHomeConfiguration;

  sorted = lib.sort (a: b: a < b);
  has = name: packages: lib.elem name (map lib.getName packages);

  securityNames = [
    "security-disk-encryption"
    "security-secrets-age"
    "security-secrets-sops"
    "security-secure-boot"
  ];

  secretsAspects = [
    "security-disk-encryption"
    "security-secrets-age"
    "security-secrets-sops"
  ];

  nixosSecretsSystem = bareNixos (
    denLib.imports {
      class = "nixos";
      aspects = secretsAspects;
    }
    ++ [ { services.userborn.enable = true; } ]
  );
  nixosSecrets = nixosSecretsSystem.config;

  nixosSecureBoot =
    (bareNixos (
      denLib.imports {
        class = "nixos";
        aspects = [ "security-secure-boot" ];
      }
    )).config;

  darwinAspects = [
    "security-secrets-age"
    "security-secrets-sops"
  ];

  darwinSecretsSystem = bareDarwinSystem (
    denLib.imports {
      class = "darwin";
      aspects = darwinAspects;
    }
  );
  darwinSecrets = darwinSecretsSystem.config;

  homeAgeConfiguration = bareHomeConfiguration (
    denLib.imports {
      class = "homeManager";
      aspects = [ "security-secrets-age" ];
    }
  );
  homeAge = homeAgeConfiguration.config;

  assertions = [
    # ---------------------------------------------------------------- instantiation
    {
      name = "the security aspects instantiate in all three classes";
      expected = {
        nixos = true;
        darwin = true;
        home = true;
      };
      actual = {
        nixos = builtins.isString nixosSecretsSystem.config.system.build.toplevel.drvPath;
        darwin = builtins.isString darwinSecrets.system.build.toplevel.drvPath;
        home = builtins.isString homeAge.home.activationPackage.drvPath;
      };
    }
    {
      name = "each security aspect emits the classes its old module had";
      expected = {
        security-disk-encryption = [ "nixos" ];
        security-secrets-age = [
          "darwin"
          "homeManager"
          "nixos"
        ];
        security-secrets-sops = [
          "darwin"
          "nixos"
        ];
        security-secure-boot = [ "nixos" ];
      };
      actual = lib.mapAttrs (_: sorted) (lib.getAttrs securityNames denLib.pairs);
    }

    # ---------------------------------------------------------------- security-disk-encryption
    #
    # This is the gap the batch closes. No den file wrote `security.tpm2.enable` before it.
    {
      name = "the disk-encryption aspect turns the TPM2 stack on";
      expected = true;
      actual = nixosSecrets.security.tpm2.enable;
    }
    {
      name = "the disk-encryption aspect brings the encryption command set with it";
      expected = {
        sbctl = true;
        tpm2-tools = true;
        cryptsetup = true;
      };
      actual = {
        sbctl = has "sbctl" nixosSecrets.environment.systemPackages;
        tpm2-tools = has "tpm2-tools" nixosSecrets.environment.systemPackages;
        cryptsetup = has "cryptsetup" nixosSecrets.environment.systemPackages;
      };
    }

    # ---------------------------------------------------------------- security-secure-boot
    {
      name = "the secure-boot aspect replaces systemd-boot with lanzaboote";
      expected = {
        systemdBoot = false;
        lanzaboote = true;
        pkiBundle = "/etc/secureboot";
      };
      actual = {
        systemdBoot = nixosSecureBoot.boot.loader.systemd-boot.enable;
        lanzaboote = nixosSecureBoot.boot.lanzaboote.enable;
        pkiBundle = toString nixosSecureBoot.boot.lanzaboote.pkiBundle;
      };
    }
    {
      name = "the secure-boot aspect brings the encryption command set with it";
      expected = true;
      actual = has "sbctl" nixosSecureBoot.environment.systemPackages;
    }

    # ---------------------------------------------------------------- security-secrets-age
    {
      name = "the age aspect keeps the four sops key settings of the old module";
      expected = {
        gnupgSshKeyPaths = [ ];
        ageSshKeyPaths = [ ];
        generateKey = false;
        keyFile = "/var/lib/sops-nix/key.txt";
      };
      actual = {
        gnupgSshKeyPaths = nixosSecrets.sops.gnupg.sshKeyPaths;
        ageSshKeyPaths = nixosSecrets.sops.age.sshKeyPaths;
        generateKey = nixosSecrets.sops.age.generateKey;
        keyFile = toString nixosSecrets.sops.age.keyFile;
      };
    }
    {
      name = "the new keyFile option feeds sops.age.keyFile, in both host classes";
      expected = {
        nixos = "/var/lib/my-keys/age.txt";
        darwin = "/var/lib/sops-nix/key.txt";
      };
      actual = {
        nixos =
          toString
            (bareNixos (
              denLib.imports {
                class = "nixos";
                aspects = [ "security-secrets-age" ];
              }
              ++ [ { kdn.security.secrets.age.keyFile = "/var/lib/my-keys/age.txt"; } ]
            )).config.sops.age.keyFile;
        darwin = toString darwinSecrets.sops.age.keyFile;
      };
    }
    {
      name = "the generator set folds into one command and keeps the SSH source";
      expected = {
        folded = "kdn-sops-age-gen-keys";
        sources = [ "kdn-sops-age-gen-keys-ssh" ];
      };
      actual = {
        folded = lib.getName nixosSecrets.kdn.security.secrets.age.genScripts;
        sources = map lib.getName nixosSecrets.kdn.security.secrets.age.genScripts.passthru.scripts;
      };
    }
    {
      name = "the age plugin list stays empty until a hardware aspect fills it";
      expected = [ ];
      actual = nixosSecrets.kdn.security.secrets.age.plugins;
    }
    {
      name = "the age aspect ships its three commands in every class";
      expected = {
        nixosAge = true;
        nixosSshToAge = true;
        nixosGenerator = true;
        darwinAge = true;
        homeAge = true;
      };
      actual = {
        nixosAge = has "age" nixosSecrets.environment.systemPackages;
        nixosSshToAge = has "ssh-to-age" nixosSecrets.environment.systemPackages;
        nixosGenerator = has "kdn-sops-age-gen-keys" nixosSecrets.environment.systemPackages;
        darwinAge = has "age" darwinSecrets.environment.systemPackages;
        homeAge = has "age" homeAge.home.packages;
      };
    }
    {
      name = "the NixOS unit runs the pre-start script and carries the plugin path";
      # sops-nix writes its own entries into the same `path` list, so an exact list is wrong. The
      # probe asks that every plugin of the aspect reaches the list. A bare subject names none.
      expected = {
        preStart = true;
        plugins = [ ];
        pathHoldsPlugins = true;
      };
      actual = {
        preStart = lib.hasInfix "kdn-sops-pre-start" nixosSecrets.systemd.services.sops-install-secrets.preStart;
        plugins = nixosSecrets.kdn.security.secrets.age.plugins;
        pathHoldsPlugins = lib.all (
          plugin: lib.elem plugin nixosSecrets.systemd.services.sops-install-secrets.path
        ) nixosSecrets.kdn.security.secrets.age.plugins;
      };
    }
    {
      name = "the age overlay wraps the sops command in both host classes";
      # `lib.getName` cuts the version and every word after it, so the suffix needs the raw
      # `name`. `buildEnv` sets `name` and no `pname`.
      expected = {
        nixos = true;
        darwin = true;
      };
      actual = {
        nixos = lib.hasSuffix "-sops-age-wrapped" nixosSecretsSystem.pkgs.sops.name;
        darwin = lib.any (
          p: lib.hasSuffix "-sops-age-wrapped" (p.name or "")
        ) darwinSecrets.environment.systemPackages;
      };
    }

    # ---------------------------------------------------------------- security-secrets-sops
    {
      name = "the sops aspect discovers no file until a consumer names one";
      expected = {
        files = { };
        defaultFile = null;
        hasDefaultFile = false;
      };
      actual = {
        files = nixosSecrets.kdn.security.secrets.sops.files;
        defaultFile = nixosSecrets.kdn.security.secrets.sops.defaultFile;
        hasDefaultFile = nixosSecrets.kdn.security.secrets.sops.hasDefaultFile;
      };
    }
    {
      name = "an absent defaultFile answers false and reads no path";
      expected = false;
      actual =
        (bareNixos (
          denLib.imports {
            class = "nixos";
            aspects = secretsAspects;
          }
          ++ [
            { services.userborn.enable = true; }
            { kdn.security.secrets.sops.defaultFile = "/den-mvp/absent.sops.yaml"; }
          ]
        )).config.kdn.security.secrets.sops.hasDefaultFile;
    }
    {
      name = "the two nested views stay empty while no secret exists";
      expected = {
        placeholders = { };
        secrets = { };
        sopsSecrets = { };
      };
      actual = {
        placeholders = nixosSecrets.kdn.security.secrets.sops.placeholders;
        secrets = nixosSecrets.kdn.security.secrets.sops.secrets;
        sopsSecrets = nixosSecrets.sops.secrets;
      };
    }
    {
      name = "the sops aspect ships the two commands, in both host classes";
      expected = {
        nixosSops = true;
        nixosCommand = true;
        darwinCommand = true;
      };
      actual = {
        nixosSops = lib.any (
          p: lib.hasInfix "sops" (lib.getName p)
        ) nixosSecrets.environment.systemPackages;
        nixosCommand = has "kdn-sops-secrets" nixosSecrets.environment.systemPackages;
        darwinCommand = has "kdn-sops-secrets" darwinSecrets.environment.systemPackages;
      };
    }
    {
      name = "the jsonTemplate overlay reaches the package set of both host classes";
      expected = {
        nixos = true;
        darwin = true;
      };
      actual = {
        nixos = nixosSecretsSystem.pkgs ? jsonTemplate;
        darwin = darwinSecretsSystem.pkgs ? jsonTemplate;
      };
    }
    {
      name = "the unwrap marker keeps the shape the old module produced";
      expected = "<UNWRAP:1:UNWRAP>";
      actual = nixosSecretsSystem.pkgs.jsonTemplate.unwrap "1";
    }
    {
      name = "the sops aspect orders the secrets target behind the install unit";
      expected = {
        after = [ "sops-install-secrets.service" ];
        bindsTo = [ "sops-install-secrets.service" ];
      };
      actual = {
        after = nixosSecrets.systemd.targets.kdn-secrets.after;
        bindsTo = nixosSecrets.systemd.targets.kdn-secrets.bindsTo;
      };
    }
    {
      name = "the sops aspect brings the secrets policy aspect through its include";
      expected = {
        allow = true;
        allowed = true;
      };
      actual = {
        allow = nixosSecrets.kdn.security.secrets.allow;
        allowed = nixosSecrets.kdn.security.secrets.allowed;
      };
    }
    {
      name = "a machine that allows no secret writes no sops template";
      expected = {
        templates = [ ];
        secrets = [ ];
      };
      actual =
        let
          denied =
            (bareNixos (
              denLib.imports {
                class = "nixos";
                aspects = secretsAspects;
              }
              ++ [
                { services.userborn.enable = true; }
                { kdn.security.secrets.allow = false; }
              ]
            )).config;
        in
        {
          templates = builtins.attrNames denied.sops.templates;
          secrets = builtins.attrNames denied.sops.secrets;
        };
    }
  ];

  # ------------------------------------------------------------------ the coverage rows
  instantiatedBy = {
    security-disk-encryption = "den-eval-security (bare nixos, the TPM2 leaf)";
    security-secrets-age = "den-eval-security (bare nixos, bare darwin, bare home)";
    security-secrets-sops = "den-eval-security (bare nixos, bare darwin)";
    security-secure-boot = "den-eval-security (bare nixos, value reads)";
  };
in
{
  inherit assertions instantiatedBy;
}

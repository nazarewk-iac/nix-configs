{ lib, pkgs, config, self, ... }:
let
  cfg = config.kdn.security.secrets;
in
{
  options.kdn.security.secrets = {
    enable = lib.mkEnableOption "Nix secrets setup";
    allow = lib.mkOption {
      type = with lib.types; bool;
      default = true;
    };
    allowed = lib.mkOption {
      readOnly = true;
      type = with lib.types; bool;
      default = cfg.allow && cfg.enable;
    };
    sshKeyFiles = lib.mkOption {
      type = with lib.types; listOf path;
      default = [ ];
      apply = paths: lib.pipe paths [
        (builtins.map builtins.readFile paths)
      ];
    };
    age.identities = lib.mkOption {
      type = lib.types.listOf lib.types.submodule {
        options = {
          value = lib.mkOption {
            type = lib.types.str;
          };
          description = lib.mkOption {
            type = lib.types.str;
          };
        };
      };
      default = [ ];
    };
    age.genScripts = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
      apply = packages: lib.pipe packages [
        (builtins.map lib.getExe)
        (builtins.concatStringsSep "\n")
        (text: pkgs.writeShellApplication {
          inherit text;
          name = "kdn-sops-age-gen-keys";
          derivationArgs.passthru.scripts = packages;
          runtimeInputs = with pkgs; [
            coreutils
            ssh-to-age
          ];
        })
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.allow || (config.sops.secrets == { } && config.sops.templates == { });
        message = "`sops.secrets` and `sops.templates` must be empty when `kdn.security.secrets.allow` is `false`";
      }
    ];

    environment.systemPackages = (with pkgs; [
      cfg.age.genScripts
      (pkgs.callPackage ./sops/package.nix { })
      age
      ssh-to-age
      ssh-to-pgp
    ]);

    sops.defaultSopsFile = "${self}/default.unattended.sops.yaml";
    # see https://github.com/Mic92/sops-nix/issues/65
    # note: SSH key gets imported automatically
    sops.gnupg.sshKeyPaths = [ ];
    sops.age.sshKeyPaths = [ ];
    sops.age.keyFile = "/var/lib/sops-nix/key.txt";
    sops.age.generateKey = false;

    kdn.security.secrets.age.genScripts = [
      (pkgs.writeShellApplication {
        name = "kdn-sops-age-gen-keys-ssh";
        runtimeInputs = with pkgs; [
          coreutils
          ssh-to-age
        ];
        text = ''
          if test -e /etc/ssh/ssh_host_ed25519_key; then
            ssh-to-age -i /etc/ssh/ssh_host_ed25519_key -private-key
          fi
        '';
      })
    ];
    system.activationScripts.setupSecrets.deps = [ "generateAgeKeys" ];
    system.activationScripts.generateAgeKeys =
      let
        escapedKeyFile = lib.escapeShellArg config.sops.age.keyFile;
      in
      ''
        mkdir -p $(dirname ${escapedKeyFile})
        printf "Rendering %s\n" ${escapedKeyFile}
        ${lib.getExe cfg.age.genScripts} >${escapedKeyFile}
      '';
  };
}

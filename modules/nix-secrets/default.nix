{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.direnv;
in
{
  options.kdn.nix-secrets = {
    enable = lib.mkEnableOption "sops-nix setup";
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
  };

  config = lib.mkIf cfg.enable {
    kdn.hardware.yubikey.enable = true;
    environment.systemPackages = with pkgs; [
      (pkgs.callPackage ./sops/package.nix { })
      age
      ssh-to-age
      ssh-to-pgp
    ];
    sops.age.keyFile = "/var/lib/sops-nix/key.txt";
    sops.age.generateKey = true;
  };
}

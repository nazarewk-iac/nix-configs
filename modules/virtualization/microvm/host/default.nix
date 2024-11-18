{
  lib,
  pkgs,
  config,
  self,
  system,
  ...
}: let
  cfg = config.kdn.virtualization.microvm.host;
in {
  imports = [
    self.inputs.microvm.nixosModules.host
  ];

  options.kdn.virtualization.microvm.host = {
    enable = lib.mkEnableOption "microvm host config";

    flake.nixpkgs = lib.mkOption {
      default = self.inputs.nixpkgs;
    };
    flake.microvm = lib.mkOption {
      default = self.inputs.microvm;
    };
  };

  config = lib.mkMerge [
    {
      microvm.host.enable = cfg.enable;
      kdn.virtualization.microvm.guest.nonMinimal = true;
    }
    (lib.mkIf cfg.enable {
      # see https://github.com/astro/microvm.nix/blob/24136ffe7bb1e504bce29b25dcd46b272cbafd9b/examples/microvms-host.nix
      nix.registry = {
        nixpkgs.flake = cfg.flake.nixpkgs;
        microvm.flake = cfg.flake.microvm;
      };

      nix.settings.trusted-public-keys = [
        "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys="
      ];

      nix.settings.substituters = [
        "https://microvm.cachix.org"
      ];

      environment.systemPackages = with cfg.flake.microvm.packages.${system}; [
        microvm
        mktuntap
        prebuilt # see https://github.com/astro/microvm.nix/blob/24136ffe7bb1e504bce29b25dcd46b272cbafd9b/flake.nix#L45-L55
      ];
    })
  ];
}

{
  lib,
  pkgs,
  config,
  self,
  system,
  ...
}: let
  cfg = config.kdn.virtualization.microvm.guest;
in {
  imports = [
    self.inputs.microvm.nixosModules.microvm
  ];
  options.kdn.virtualization.microvm.guest = {
    enable = lib.mkEnableOption "microvm guest config";
    nonMinimal = lib.mkEnableOption "opt-out on guest config";
  };

  config = lib.mkMerge [
    # `microvm.guest.enable` defaults to `true`
    {microvm.guest.enable = cfg.enable;}
    (lib.mkIf cfg.enable {
      microvm.shares = [
        {
          # use "virtiofs" for MicroVMs that are started by systemd
          proto = "virtiofs";
          tag = "ro-store";
          # a host's /nix/store will be picked up so that the
          # size of the /dev/vda can be reduced.
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
        }
      ];
      # see https://github.com/astro/microvm.nix/blob/c022372b917ecc4ed7df51ff30395421a74b0495/nixos-modules/microvm/mounts.nix#L23-L35
      fileSystems."/nix/store".fsType = lib.mkForce config.microvm.bootDiskType;
    })
    (lib.mkIf cfg.nonMinimal (
      let
        default = lib.mkOverride (lib.modules.defaultOverridePriority + 1);
      in {
        # counteract https://github.com/nazarewk/nixpkgs/blob/d40fea9aeb8840fea0d377baa4b38e39b9582458/nixos/modules/profiles/minimal.nix#L8-L21
        # imported by https://github.com/astro/microvm.nix/blob/940cafd63413dc022ca3013709efcf96afe95b77/nixos-modules/microvm/system.nix#L8-L10
        documentation.enable = default true;
        documentation.nixos.enable = default true;
        programs.command-not-found.enable = default true;
        xdg.autostart.enable = default true;
        xdg.icons.enable = default true;
        xdg.mime.enable = default true;
        xdg.sounds.enable = default true;
      }
    ))
  ];
}

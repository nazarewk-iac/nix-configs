# `kdn.programs.kdeconnect`, as a den aspect.
# It ports `modules/universal/programs/kdeconnect/default.nix`.
#
# The NixOS target exists for one reason: `programs.kdeconnect.enable` opens the firewall ports.
{ kdn, ... }:
{
  kdn.program-kdeconnect.includes = [ kdn.apps ];

  kdn.program-kdeconnect.nixos.programs.kdeconnect.enable = true;

  kdn.program-kdeconnect.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      config = lib.mkMerge [
        {
          kdn.apps.kdeconnect = {
            enable = true;
            package.original = pkgs.kdePackages.kdeconnect-kde;
            # On Linux the user service below installs the package.
            package.install = pkgs.stdenv.hostPlatform.isDarwin;
            dirs.config = [ "kdeconnect" ];
          };
        }
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          services.kdeconnect.enable = true;
          services.kdeconnect.indicator = true;
          services.kdeconnect.package = config.kdn.apps.kdeconnect.package.final;
        })
      ];
    };
}

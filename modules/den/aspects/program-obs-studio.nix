# `kdn.programs.obs-studio`, as a den aspect.
# It ports `modules/universal/programs/obs-studio/default.nix`.
#
# The old module pushes the persist directory into Home Manager through
# `home-manager.sharedModules`. den holds no such bridge, so the persist write moves into a
# `homeManager` target of the same aspect.
{ kdn, ... }:
{
  kdn.program-obs-studio.includes = [ kdn.apps ];

  kdn.program-obs-studio.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.obs-studio;
    in
    {
      options.kdn.programs.obs-studio.package = lib.mkPackageOption pkgs "obs-studio" { };

      options.kdn.programs.obs-studio.plugins = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = with pkgs.obs-studio-plugins; [
          input-overlay
          obs-backgroundremoval
          obs-pipewire-audio-capture
          wlrobs
        ];
        description = ''
          Plugins the aspect passes to `programs.obs-studio.plugins`.

          Two plain definitions of this list concatenate. Never put `lib.mkDefault` on it — a plain
          definition then replaces the default instead of adding to it.
        '';
      };

      config = {
        programs.obs-studio.enable = true;
        programs.obs-studio.package = cfg.package;
        programs.obs-studio.plugins = cfg.plugins;
        programs.obs-studio.enableVirtualCamera = true;
      };
    };

  kdn.program-obs-studio.homeManager = {
    kdn.apps."obs-studio" = {
      enable = true;
      # The NixOS target installs the package system wide.
      package.install = false;
      dirs.config = [ "obs-studio" ];
    };
  };
}

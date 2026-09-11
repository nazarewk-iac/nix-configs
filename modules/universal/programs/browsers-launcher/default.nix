{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.browsers-launcher;
in
{
  options.kdn.programs.browsers-launcher = {
    enable = lib.mkEnableOption "`browsers` selector setup";

    casks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "browsers" ];
      example = [ ];
      description = ''
        Homebrew casks the Darwin route installs. The write also needs `kdn.homebrew.enable`, so
        a consumer that runs its own Homebrew receives no cask from this module.
      '';
    };
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.programs.browsers-launcher = cfg; } ];
    })
    {
      kdn.apps.browsers = {
        enable = lib.mkDefault cfg.enable;
        dirs.cache = [ ];
        dirs.config = [ "software.Browsers" ];
        dirs.data = [ ];
        dirs.disposable = [ ];
        dirs.reproducible = [ ];
        dirs.state = [ ];
      };
    }
    (kdnConfig.util.ifTypes [ "darwin" ] (
      lib.mkIf cfg.enable {
        kdn.apps.browsers.package.install = false;
        homebrew.casks = lib.mkIf config.kdn.homebrew.enable cfg.casks;
      }
    ))
  ];
}

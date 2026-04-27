{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.office;
in
{
  options.kdn.programs.office = {
    enable = lib.mkEnableOption "Office suite setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.programs.office = lib.mkDefault cfg; } ];
      })
      (kdnConfig.util.ifNotHMParent {
        kdn.apps.libreoffice = {
          enable = true;
          package.original = if pkgs.stdenv.isDarwin then pkgs.libreoffice-bin else pkgs.libreoffice;
          dirs.cache = [ ];
          dirs.config = [ "libreoffice" ];
          dirs.data = [ ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [ ];
          files.cache = [ ];
        };
      })
    ]
  );
}

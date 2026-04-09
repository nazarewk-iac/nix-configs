{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.ente-photos;
in
{
  options.kdn.programs.ente-photos = {
    enable = lib.mkEnableOption "Ente Photos Desktop setup";
    #package = lib.mkPackageOption pkgs ["kdn" "ente-photos-desktop"] {};
    package = lib.mkPackageOption pkgs [ "ente-desktop" ] { };
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.programs.ente-photos = lib.mkDefault cfg; } ];
    })
    (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            kdn.apps.ente-photos-desktop = {
              enable = true;
              package.original = cfg.package;
              dirs.cache = [ "ente" ];
              dirs.config = [ "ente" ];
              dirs.data = [ ];
              dirs.disposable = [ ];
              dirs.reproducible = [ ];
              dirs.state = [ ];
            };
          }
        ]
      )
    ))
  ];
}

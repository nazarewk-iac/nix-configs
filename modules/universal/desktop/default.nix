{
  lib,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.desktop.enable = lib.mkOption {
    type = with lib.types; bool;
    default = false;
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [{kdn.desktop.enable = config.kdn.desktop.enable;}];
    })
  ];
}

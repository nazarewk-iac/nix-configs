{
  lib,
  config,
  kdnConfig,
  pkgs,
  ...
}:
{
  options.kdn.env.packages = lib.mkOption {
    type = with lib.types; listOf package;
    default = [ ];
  };
  options.kdn.env.variables = lib.mkOption {
    type = with lib.types; attrsOf str;
    default = { };
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHM {
      home.packages = config.kdn.env.packages;
      home.sessionVariables = config.kdn.env.variables;
    })
    (kdnConfig.util.ifTypes [ "darwin" ] {
      environment.systemPackages = config.kdn.env.packages;
      environment.variables = config.kdn.env.variables;
    })
    (kdnConfig.util.ifTypes [ "nixos" ] {
      environment.systemPackages = config.kdn.env.packages;
      environment.sessionVariables = config.kdn.env.variables;
    })
  ];
}

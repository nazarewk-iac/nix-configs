{
  lib,
  pkgs,
  config,
  ...
}: {
  config = {
    home.packages = config.kdn.env.packages;
    home.sessionVariables = config.kdn.env.variables;
  };
}

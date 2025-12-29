{
  lib,
  pkgs,
  config,
  ...
}: {
  config = {
    environment.systemPackages = config.kdn.env.packages;
    environment.sessionVariables = config.kdn.env.variables;
  };
}

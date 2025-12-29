{
  lib,
  pkgs,
  config,
  ...
}: {
  config = {
    environment.systemPackages = config.kdn.env.packages;
    environment.variables = config.kdn.env.variables;
  };
}

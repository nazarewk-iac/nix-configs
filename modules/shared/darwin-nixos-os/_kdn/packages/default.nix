{
  lib,
  pkgs,
  config,
  ...
}: {
  config = {
    environment.systemPackages = config.kdn.packages;
  };
}

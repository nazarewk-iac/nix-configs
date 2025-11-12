{
  lib,
  pkgs,
  config,
  ...
}: {
  config = {
    home.packages = config.kdn.packages;
  };
}

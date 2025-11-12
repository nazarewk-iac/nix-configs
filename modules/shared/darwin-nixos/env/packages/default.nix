{
  lib,
  pkgs,
  config,
  ...
}: {
  config = {
    environment.systemPackages = config.kdn.env.packages;
  };
}

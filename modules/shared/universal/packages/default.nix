{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.packages;
in {
  options.kdn.packages = lib.mkOption {
    type = with lib.types; types.listOf types.package;
    default = [];
  };
}

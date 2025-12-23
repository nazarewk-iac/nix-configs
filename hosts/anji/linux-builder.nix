{
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    # kdnConfig.self.nixosModules.default
  ];
  config = lib.mkMerge [
    {

    }
  ];
}

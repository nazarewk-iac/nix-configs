{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.emulation.wine;
in {
  options.kdn.emulation.wine = {
    enable = lib.mkEnableOption "Wine";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            # TODO: cut out the Wine32 package somehow for other platforms? seems to be pulled in automatically
            assertion = pkgs.stdenv.hostPlatform.isx86;
            message = "Wine32 (kdn.emulation.wine) is only available on x86 architectures!";
          }
          {
            assertion = config.kdn.desktop.enable;
            message = "kdn.emulation.wine: available only on desktop";
          }
        ];
      }
      {
        kdn.apps.wine = {
          enable = true;
          package.original = pkgs.wine-wayland;
          dirs.cache = [];
          dirs.config = [];
          dirs.data = ["/.wine"];
          dirs.disposable = [];
          dirs.reproducible = [];
          dirs.state = [];
        };
      }
    ]
  );
}

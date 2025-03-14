{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hw.intel-graphics-fix;
in {
  options.kdn.hw.intel-graphics-fix = {
    enable = lib.mkEnableOption "Intel HD Graphics fix";
  };

  config = lib.mkIf cfg.enable {
    # should fix mesa crashes
    # - https://gitlab.freedesktop.org/mesa/mesa/-/issues/5864
    # - https://gitlab.freedesktop.org/mesa/mesa/-/issues/5600
    # - https://matrix.to/#/!KqkRjyTEzAGRiZFBYT:nixos.org/$U1Qhgf2AX_tVar9LuBrzOnNFYeoGkIntkv5OLs0D-dM?via=nixos.org&via=matrix.org&via=tchncs.de
    environment.variables = {
      MESA_LOADER_DRIVER_OVERRIDE = "i965";
    };
    nixpkgs.overlays = [
      (final: prev: {
        # mesa = nixpkgs-mesa.legacyPackages.x86_64-linux.mesa;
      })
    ];
  };
}

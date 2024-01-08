{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.networking.netmaker.client;
in
{
  options.kdn.networking.netmaker.client = {
    enable = lib.mkEnableOption "Netmaker client";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.netclient;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [{
    environment.systemPackages = with pkgs; [
      cfg.package
    ];
  }]);
}

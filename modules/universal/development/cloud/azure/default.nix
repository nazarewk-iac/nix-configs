{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.cloud.azure;
in
{
  options.kdn.development.cloud.azure = {
    enable = lib.mkEnableOption "Azure cloud development";
  };

  config = lib.mkIf cfg.enable {
    kdn.development.dotnet.enable = true;
    kdn.env.packages = with pkgs; [
      powershell
      azure-cli
    ];
  };
}

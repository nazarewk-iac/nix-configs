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

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      kdn.development.dotnet.enable = true;
      environment.systemPackages = with pkgs; [
        powershell
        azure-cli
      ];
    }
  );
}

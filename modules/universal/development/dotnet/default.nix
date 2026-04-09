{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.dotnet;
in
{
  options.kdn.development.dotnet = {
    enable = lib.mkEnableOption ".NET development";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      # see https://nixos.wiki/wiki/DotNET
      programs.nix-ld.enable = true;
      environment.sessionVariables = {
        DOTNET_ROOT = "${pkgs.dotnet-sdk}";
      };
      environment.systemPackages = with pkgs; [
        dotnet-sdk
        dotnet-runtime
      ];
    }
  );
}

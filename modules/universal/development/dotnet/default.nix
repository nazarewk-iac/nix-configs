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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          dotnet-sdk
          dotnet-runtime
        ];
        kdn.env.variables = {
          # see https://nixos.wiki/wiki/DotNET
          DOTNET_ROOT = "${pkgs.dotnet-sdk}";
        };
      }
      (kdnConfig.util.ifTypes [ "nixos" ] {
        # see https://nixos.wiki/wiki/DotNET
        programs.nix-ld.enable = true;
      })
    ]
  );
}

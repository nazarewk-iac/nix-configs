{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.development.nix;
in {
  options.kdn.development.nix = {
    enable = lib.mkEnableOption "nix development/debugging";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {kdn.toolset.nix.enable = true;}
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [{kdn.development.nix.enable = true;}];
    })
    (kdnConfig.util.ifNotHMParent {
      kdn.env.packages = with pkgs; ([
          #self.inputs.nixpkgs-update.defaultPackage.${system}
          nixos-anywhere

          # language servers
          nil
          nixd
        ]
        ++ [
          devenv
        ]
        ++ [
          # formatters
          alejandra
          nixfmt-rfc-style
          kdn.kdn-nix-fmt
        ]);
    })
  ]);
}

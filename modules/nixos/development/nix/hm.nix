{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.nix;
in {
  options.kdn.development.nix = {
    enable = lib.mkEnableOption "nix development/debugging";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; ([
        #self.inputs.nixpkgs-update.defaultPackage.${system}
        nix-update
        nixos-anywhere
        # check for packages in cache
        nix-weather
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

    programs.helix.extraPackages = with pkgs; [
      nil
      nixd
    ];

    programs.helix.languages.language = [
      {
        name = "nix";
        auto-format = true;
        formatter = {
          command = lib.getExe pkgs.kdn.kdn-nix-fmt;
        };
      }
    ];
  };
}

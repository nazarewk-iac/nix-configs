{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.development.nix;
in
{
  options.kdn.development.nix = {
    enable = lib.mkEnableOption "nix development/debugging";
  };

  config = lib.mkIf cfg.enable {
    kdn.programs.nix-utils.enable = true;
    home-manager.sharedModules = [ { kdn.development.nix.enable = true; } ];
    environment.systemPackages = with pkgs; [
      #self.inputs.nixpkgs-update.defaultPackage.${system}
      alejandra
      nix-update
      nixfmt-rfc-style
      nixos-anywhere
      nixpkgs-fmt
      # check for packages in cache
      nix-weather
      # language servers
      nil
      nixd
    ];
  };
}

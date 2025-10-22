{
  config,
  lib,
  pkgs,
  kdn,
  ...
}: let
  inherit (kdn) inputs;
in {
  imports =
    if kdn.moduleType == "nixos"
    then [inputs.stylix.nixosModules.stylix]
    else if kdn.moduleType == "nix-darwin"
    then [inputs.stylix.darwinModules.stylix]
    else if
      kdn.moduleType
      == "home-manager"
      && !(kdn.hasParentOfAnyType [
        "nixos"
        "nix-darwin"
      ])
    then [inputs.stylix.homeModules.stylix]
    else [];
  config = lib.mkMerge [
    (lib.attrsets.optionalAttrs (kdn.isOfAnyType ["nixos"]) {
      /*
      TODO: review new option added for simplifications?
       see https://github.com/danth/stylix/commit/7682713f6af1d32a33f8c4e3d3d141af5ad1761a
      */

      stylix.enable = true;
      # required to evaluate stylix
      stylix.image = lib.mkDefault (
        pkgs.fetchurl {
          # non-expiring share link
          url = "https://nc.nazarewk.pw/s/XSR3x6AkwZAiyBo/download/13754-mushrooms-toadstools-glow-photoshop-3840x2160.jpg";
          sha256 = "sha256-1d/kdFn8v0i1PTeOPytYNUB1TxsuBLNf4+nRgSOYQu4=";
        }
      );
      stylix.polarity = lib.mkDefault "dark";
      stylix.base16Scheme = lib.mkDefault ./stylix.pallette.yaml;

      stylix.cursor.name = lib.mkDefault "phinger-cursors-${config.stylix.polarity}";
      stylix.cursor.package = lib.mkDefault pkgs.phinger-cursors;
      stylix.cursor.size = lib.mkDefault 32;
      stylix.fonts.monospace.name = lib.mkDefault "Fira Code";
      stylix.fonts.monospace.package = lib.mkDefault pkgs.fira-code;
    })
    (lib.attrsets.optionalAttrs (kdn.isOfAnyType ["nixos"]) {
      fonts.fontDir.enable = true;
      fonts.packages = with pkgs; [
        fira-code
        fira-code-symbols
      ];
    })
  ];
}

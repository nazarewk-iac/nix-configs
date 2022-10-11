{ pkgs, ... }: {
  edid-generator = pkgs.callPackage ./edid-generator { };
}

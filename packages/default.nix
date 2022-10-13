{ pkgs, ... }: {
  edid-generator = pkgs.callPackage ./edid-generator { };
  linuxhw-edid-fetcher = pkgs.callPackage ./linuxhw-edid-fetcher { };
}

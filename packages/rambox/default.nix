{ stdenv, callPackage, fetchurl, lib }:

let
  mkRambox = opts: callPackage (import ./rambox.nix opts) { };
in
mkRambox rec {
  pname = "rambox";
  version = "2.0.9";

  src = {
    x86_64-linux = fetchurl {
      url = "https://github.com/ramboxapp/download/releases/download/v${version}/Rambox-${version}-linux-x64.AppImage";
      sha256 = "sha256-o2ydZodmMAYeU0IiczKNlzY2hgTJbzyJWO/cZSTfAuM=";
    };
  }.${stdenv.system} or (throw "Unsupported system: ${stdenv.system}");

  meta = with lib; {
    description = "Free and Open Source messaging and emailing app that combines common web applications into one";
    homepage = "https://rambox.pro";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = [ "i686-linux" "x86_64-linux" ];
    hydraPlatforms = [ ];
  };
}

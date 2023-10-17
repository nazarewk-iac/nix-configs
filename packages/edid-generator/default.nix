{ lib
, stdenv
, fetchFromGitHub
, dos2unix
, edid-decode
, hexdump
, zsh
}:

# Usage:
#   hardware.firmware = [(edid-generator.overrideAttrs {
#     clean = true;
#     modelines = ''
#       Modeline "PG278Q_60"      241.50   2560 2608 2640 2720   1440 1443 1448 1481   -hsync +vsync
#       Modeline "PG278Q_120"     497.75   2560 2608 2640 2720   1440 1443 1448 1525   +hsync -vsync
#       Modeline "U2711_60"       241.50   2560 2600 2632 2720   1440 1443 1448 1481   -hsync +vsync
#     '';
#   })];

stdenv.mkDerivation {
  pname = "edid-generator";
  version = "master-2023-10-17";

  # so `hardware.firmware` doesn't compress it
  compressFirmware = false;

  src = fetchFromGitHub {
    owner = "nazarewk";
    repo = "edid-generator";
    rev = "f7fd645fbd106db508954f1a3e01b6a38e95d65b";
    sha256 = "sha256-CoEcAl5680fCOF2XxxGSiBs6AqdsbBbaM+ENAC2lOU8=";
  };

  nativeBuildInputs = [ dos2unix edid-decode hexdump zsh ];

  postPatch = ''
    patchShebangs modeline2edid
  '';

  passAsFile = [ "modelines" ];
  clean = false;
  modelines = "";

  configurePhase = ''
    test "$clean" == 0 || rm *x*.S
    ./modeline2edid - <"$modelinesPath"

    for file in *.S ; do
      echo "--- $file"
      cat "$file"
    done
    make clean all
  '';

  installPhase = ''
    for file in *.bin ; do
      # validate
      edid-decode <"$file"
      install -Dm 444 "$file" -t "$out/lib/firmware/edid"
    done
  '';

  meta = {
    description = "Hackerswork to generate an EDID blob from given Xorg Modelines";
    homepage = "https://github.com/nazarewk/edid-generator";
    license = lib.licenses.gpl3;
    maintainers = with lib.maintainers; [ flokli nazarewk ];
    platforms = lib.platforms.all;
    broken = stdenv.isDarwin; # never built on Hydra https://hydra.nixos.org/job/nixpkgs/trunk/edid-generator.x86_64-darwin
  };
}

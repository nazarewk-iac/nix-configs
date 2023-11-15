{ lib
, stdenv
, fetchFromGitHub
, fetchpatch
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
  version = "master-2023-11-15";

  # so `hardware.firmware` doesn't compress it
  compressFirmware = false;

  src = fetchFromGitHub {
    owner = "akatrevorjay";
    repo = "edid-generator";
    rev = "9430c121e0b31d8d60799379f73722f08f2e62a1";
    sha256 = "sha256-CoEcAl5680fCOF2XxxGSiBs6AqdsbBbaM+ENAC2lOU8=";
  };
  patches = [
    (fetchpatch {
      # https://github.com/akatrevorjay/edid-generator/pull/29
      url = "https://github.com/nazarewk/edid-generator/compare/9430c121e0b31d8d60799379f73722f08f2e62a1...cc9572bb94cdde0ff6e930bfd9354a3c8badc168.patch";
      sha256 = "sha256-7uj3Vf8bnNtv0imSDcBS4Rc0Zeq+/s1Ua04DeL71Gss=";
    })
  ];

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
    make clean
  '';

  buildPhase = ''
    make all
  '';

  doCheck = true;
  checkPhase = ''
    for file in *.bin ; do
      echo "validating $file"
      edid-decode <"$file"
    done
  '';

  installPhase = ''
    install -Dm 444 *.bin -t "$out/lib/firmware/edid"
  '';

  meta = {
    description = "Hackerswork to generate an EDID blob from given Xorg Modelines";
    homepage = "https://github.com/akatrevorjay/edid-generator";
    license = lib.licenses.gpl3;
    maintainers = with lib.maintainers; [ flokli nazarewk ];
    platforms = lib.platforms.all;
    broken = stdenv.isDarwin; # never built on Hydra https://hydra.nixos.org/job/nixpkgs/trunk/edid-generator.x86_64-darwin
  };
}

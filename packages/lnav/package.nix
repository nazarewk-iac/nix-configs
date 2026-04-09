{
  lib,
  stdenv,
  fetchpatch,
  fetchFromGitHub,
  pcre2,
  sqlite,
  readline,
  zlib,
  bzip2,
  autoconf,
  automake,
  curl,
  buildPackages,
  re2c,
  gpm,
  libarchive,
  nix-update-script,
  cargo,
  rustPlatform,
  rustc,
  libunistring,
  prqlSupport ? stdenv.hostPlatform == stdenv.buildPlatform,
}:
let
  version = "0.13.1-rc1";
  srcHash = "sha256-hV7Wd/KyEumHpEFBZnou8TC0+olbAD4dWP6kEXuZSHA=";
  cargoHash = "sha256-hXjn2CF4FxCfDzikWif9hGWRmlIJI+nxbcV8EBEWxis=";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "lnav";
  version = version;

  src = fetchFromGitHub {
    owner = "tstack";
    repo = "lnav";
    tag = "v${finalAttrs.version}";
    hash = srcHash;
  };

  patches = [
  ];

  enableParallelBuilding = true;

  separateDebugInfo = true;

  strictDeps = true;

  depsBuildBuild = [ buildPackages.stdenv.cc ];

  nativeBuildInputs = [
    autoconf
    automake
    zlib
    curl.dev
    re2c
  ]
  ++ lib.optionals prqlSupport [
    cargo
    rustPlatform.cargoSetupHook
    rustc
  ];

  buildInputs = [
    bzip2
    pcre2
    readline
    sqlite
    curl
    libarchive
    libunistring
  ]
  ++ lib.optionals (!stdenv.hostPlatform.isDarwin) [
    gpm
  ];

  cargoDeps = rustPlatform.fetchCargoVendor {
    src = "${finalAttrs.src}/src/third-party/prqlc-c";
    hash = cargoHash;
  };

  cargoRoot = "src/third-party/prqlc-c";

  preConfigure = ''
    ./autogen.sh
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    homepage = "https://github.com/tstack/lnav";
    description = "Logfile Navigator";
    longDescription = ''
      The log file navigator, lnav, is an enhanced log file viewer that takes
      advantage of any semantic information that can be gleaned from the files
      being viewed, such as timestamps and log levels. Using this extra
      semantic information, lnav can do things like interleaving messages from
      different files, generate histograms of messages over time, and providing
      hotkeys for navigating through the file. It is hoped that these features
      will allow the user to quickly and efficiently zero in on problems.
    '';
    downloadPage = "https://github.com/tstack/lnav/releases";
    license = lib.licenses.bsd2;
    maintainers = with lib.maintainers; [
      dochang
      symphorien
      pcasaretto
    ];
    platforms = lib.platforms.unix;
    mainProgram = "lnav";
  };
})

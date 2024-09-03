# this doesn't build portable Go binaries or fails completely after applying `musl` patches
# use ./build.sh to build & run manuallys
{ stdenv
, lib
, nixosTests
, nix-update-script
, buildGoModule
, fetchFromGitHub
, installShellFiles
, pkg-config
, gtk3
, libayatana-appindicator
, libX11
, libXcursor
, libXxf86vm
, Cocoa
, IOKit
, Kernel
, UserNotifications
, WebKit
, ui ? false
, netbird-ui
, musl
}:
let
  modules =
    {
      client = "netbird";
    };
in
buildGoModule rec {
  pname = "netbird";
  version = "0.28.9";

  GOOS = "linux";
  GOARCH = "arm";
  GOARM = "6";
  CGO_ENABLE = 0;

  patches = [
    ./debug.patch
    ./debug2.patch
  ];

  src = fetchFromGitHub {
    owner = "netbirdio";
    repo = "netbird";
    rev = "v${version}";
    hash = "sha256-SM288I+N645vzGmLO5hfDeFDqSJOe11+0VZVPneagHw=";
  };

  vendorHash = "sha256-UlxylKiszgB2XQ4bZI23/YY/RsFCE7OlHT3DBsRhvCk=";

  nativeBuildInputs = [ musl ];

  subPackages = lib.attrNames modules;

  ldflags = [
    "-s"
    "-w"
    "-X github.com/netbirdio/netbird/version.version=${version}"
    "-X main.builtBy=nix"
    # static linkings
    "-linkmode external"
    "-extldflags '-static -L${musl}/lib'"
  ];

  # needs network access
  doCheck = false;

  postInstall = lib.concatStringsSep "\n"
    (lib.mapAttrsToList
      (module: binary: ''
        mv $out/bin/${lib.last (lib.splitString "/" module)} $out/bin/${binary}
      '')
      modules);

  meta = with lib; {
    homepage = "https://netbird.io";
    changelog = "https://github.com/netbirdio/netbird/releases/tag/v${version}";
    description = "Connect your devices into a single secure private WireGuard®-based mesh network with SSO/MFA and simple access controls";
    license = licenses.bsd3;
    maintainers = with maintainers; [ misuzu ];
    mainProgram = if ui then "netbird-ui" else "netbird";
  };
}

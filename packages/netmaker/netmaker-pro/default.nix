{ lib
, fetchFromGitHub
, buildGoModule
, ...
}:
let
  inputs = import ../inputs.nix { inherit fetchFromGitHub; };
in
buildGoModule rec {
  pname = "netmaker-pro";
  inherit (inputs.netmaker) version src vendorHash;

  subPackages = [ "." ];

  postInstall = ''
    mv $out/bin/netmaker{,-pro}
  '';

  meta = with lib; {
    description = "WireGuard automation from homelab to enterprise - Professional Edition";
    homepage = "https://netmaker.io";
    changelog = "https://github.com/gravitl/netmaker/-/releases/v${version}";
    license = licenses.unfree;
    maintainers = with maintainers; [ urandom qjoly nazarewk ];
    mainProgram = "netmaker-pro";
  };
}

{ lib
, fetchFromGitHub
, buildGoModule
, ...
}:
let
  inputs = import ../inputs.nix { inherit fetchFromGitHub; };
in
buildGoModule rec {
  pname = "netmaker";
  inherit (inputs.netmaker) version src vendorHash;

  subPackages = [ "." ];

  meta = with lib; {
    description = "WireGuard automation from homelab to enterprise";
    homepage = "https://netmaker.io";
    changelog = "https://github.com/gravitl/netmaker/-/releases/v${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ urandom qjoly nazarewk ];
    mainProgram = "netmaker";
  };
}

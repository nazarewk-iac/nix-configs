{ lib
, buildNpmPackage
, fetchFromGitHub
, tree
, ...
}:

let
  inputs = import ../inputs.nix { inherit fetchFromGitHub; };
in
buildNpmPackage rec {
  pname = "netmaker-ui";
  inherit (inputs.netmaker-ui) version src npmDepsHash;

  installPhase = ''
    mkdir -p "$out"
    mv dist "$out/www"
  '';

  meta = with lib; {
    description = "WireGuard automation from homelab to enterprise";
    homepage = "https://netmaker.io";
    changelog = "https://github.com/gravitl/netmaker-ui-2/-/releases/v${version}";
    license = licenses.sspl;
    maintainers = with maintainers; [ nazarewk ];
  };
}

{ lib
, fetchFromGitHub
, buildGoModule
, nmInputs
, ...
}:
buildGoModule rec {
  pname = "netmaker";
  inherit (nmInputs.netmaker) version src vendorHash;

  subPackages = [ "." ];
  CGO_ENABLED = true;

  postPatch = ''
    rm -r main_ee.go pro
  '';

  meta = with lib; {
    description = "WireGuard automation from homelab to enterprise - Community Edition";
    homepage = "https://netmaker.io";
    changelog = "https://github.com/gravitl/netmaker/-/releases/v${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ urandom qjoly nazarewk ];
    mainProgram = "netmaker";
  };
}

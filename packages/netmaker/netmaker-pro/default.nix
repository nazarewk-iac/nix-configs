{ lib
, fetchFromGitHub
, buildGoModule
, nmInputs
, ...
}:
buildGoModule rec {
  pname = "netmaker-pro";
  inherit (nmInputs.netmaker) version src vendorHash;

  subPackages = [ "." ];

  CGO_ENABLED = true;
  tags = [ "ee" ];

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

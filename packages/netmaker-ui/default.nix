{ lib
, buildNpmPackage
, fetchFromGitHub
, nix-update-script
, ...
}:
buildNpmPackage rec {
  pname = "netmaker-ui";

  passthru.updateScript = nix-update-script { extraArgs = [ "--version=branch=master" ]; };
  version = "unstable-2024-01-22";

  src = fetchFromGitHub {
    owner = "nazarewk";
    repo = "netmaker-ui-2";
    rev = "3e3cb89d95819cbaee9a43f0507a89024f9d7e13";
    hash = "sha256-oDcgoerE4W7kd8fpDl3SAwsYNXpRrUSUp7PYeXkaS1g=";
  };
  npmDepsHash = "sha256-B7MdaHbwMxZKWc6KARlDqp4tzPVS0O8ChmHfspYR7Co=";

  installPhase = ''
    mkdir -p "$out/var"
    mv dist "$out/var/www"
  '';

  meta = with lib; {
    description = "WireGuard automation from homelab to enterprise";
    homepage = "https://netmaker.io";
    changelog = "https://github.com/gravitl/netmaker-ui-2/-/releases/v${version}";
    license = licenses.sspl;
    maintainers = with maintainers; [ nazarewk ];
  };
}

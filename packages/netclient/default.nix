{ lib
, buildGoModule
, fetchFromGitHub
, installShellFiles
, makeWrapper
, nix-update-script
, stdenv
, systemd
, ...
}:
buildGoModule rec {
  pname = "netclient";

  passthru.updateScript = nix-update-script { extraArgs = [ "--version=branch=master" ]; };
  version = "unstable-2024-01-22";
  src = fetchFromGitHub {
    owner = "nazarewk";
    repo = "netclient";
    rev = "1614e652824a731157b5d262899f8d4d7e024cf0";
    hash = "sha256-Mg3QYWAyN0R2oi2VfvvGQA7UsJ1NkKz2lAq3ZafIl5k=";
  };
  vendorHash = "sha256-lRXZ9iSWQEKWmeQV1ei/G4+HvqhW9U8yUv1Qb/d2jvY=";

  subPackages = [ "." ];
  CGO_ENABLED = false;
  hardeningEnabled = [ "pie" ];

  nativeBuildInputs = [
    makeWrapper
    installShellFiles
  ];

  NETCLIENT_AUTO_UPDATE = "disabled";
  NETCLIENT_INIT_TYPE = if lib.meta.availableOn stdenv.hostPlatform systemd then "systemd" else "";

  postInstall = ''
    wrapperArgs=()
    for var in "''${!NETCLIENT_@}" ; do
      test -n "''${!var}" || continue
      wrapperArgs+=( --set "$var" "''${!var}" )
    done

    wrapProgram "$out/bin/netclient" "''${wrapperArgs[@]}"

    installShellCompletion --cmd netclient \
      --bash <($out/bin/netclient completion bash) \
      --fish <($out/bin/netclient completion fish) \
      --zsh <($out/bin/netclient completion zsh)
  '';

  meta = {
    description = "Automated WireGuard® Management Client";
    homepage = "https://netmaker.io";
    changelog = "https://github.com/gravitl/netclient/releases/tag/v${version}";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ wexder nazarewk ];
    mainProgram = "netclient";
  };
}

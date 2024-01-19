{ lib
, buildGoModule
, fetchFromGitHub
, installShellFiles
, nmInputs
, ...
}:
buildGoModule rec {
  pname = "netclient";
  inherit (nmInputs.netclient) version src vendorHash;

  subPackages = [ "." ];
  CGO_ENABLED = false;
  hardeningEnabled = [ "pie" ];
  nativeBuildInputs = [
    installShellFiles
  ];

  postInstall = ''
    installShellCompletion --cmd netclient \
      --bash <($out/bin/netclient completion bash) \
      --fish <($out/bin/netclient completion fish) \
      --zsh <($out/bin/netclient completion zsh)
  '';

  meta = with lib; {
    description = "Automated WireGuard® Management Client";
    homepage = "https://netmaker.io";
    changelog = "https://github.com/gravitl/netclient/releases/tag/v${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ wexder nazarewk ];
    mainProgram = "netclient";
  };
}

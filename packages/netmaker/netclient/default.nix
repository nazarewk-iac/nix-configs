{ lib
, buildGoModule
, fetchFromGitHub
, installShellFiles
}:
let
  inputs = import ../inputs.nix { inherit fetchFromGitHub; };
in
buildGoModule rec {
  pname = "netclient";
  inherit (inputs) version;
  inherit (inputs.netclient) src vendorHash;

  subPackages = [ "." ];
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

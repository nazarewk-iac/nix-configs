{ lib
, fetchFromGitHub
, buildGoModule
, installShellFiles
, ...
}:
let
  inputs = import ../inputs.nix { inherit fetchFromGitHub; };
in
buildGoModule rec {
  pname = "nmctl";
  inherit (inputs.netmaker) version src vendorHash;

  subPackages = [ "cli" ];
  nativeBuildInputs = [
    installShellFiles
  ];

  postInstall = ''
    mv $out/bin/{cli,nmctl}

    installShellCompletion --cmd nmctl \
      --bash <($out/bin/nmctl completion bash) \
      --fish <($out/bin/nmctl completion fish) \
      --zsh <($out/bin/nmctl completion zsh)
  '';

  meta = with lib; {
    description = "WireGuard automation from homelab to enterprise";
    homepage = "https://netmaker.io";
    changelog = "https://github.com/gravitl/netmaker/-/releases/v${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ urandom qjoly nazarewk ];
    mainProgram = "nmctl";
  };
}

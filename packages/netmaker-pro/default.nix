{ lib
, fetchFromGitHub
, buildGoModule
, installShellFiles
, nix-update-script
, ...
}:
buildGoModule rec {
  pname = "netmaker-pro";

  passthru.updateScript = nix-update-script { };
  version = "0.22.0";
  src = fetchFromGitHub {
    owner = "gravitl";
    repo = "netmaker";
    rev = "v${version}";
    hash = "sha256-uplv/9P7uNYFRLI8LTUXAjKImTtLijsk2gb81vbunXY=";
  };
  vendorHash = "sha256-t7g6Tozq/QLq0/5bpXNDCJrOPTjMlvcDUaD6EGqII3Y=";


  subPackages = [ "." "cli" ];

  CGO_ENABLED = true;
  tags = [ "ee" ];

  nativeBuildInputs = [
    installShellFiles
  ];

  postInstall = ''
    mv $out/bin/{cli,nmctl-pro}
    installShellCompletion --cmd nmctl-pro \
      --bash <($out/bin/nmctl-pro completion bash) \
      --fish <($out/bin/nmctl-pro completion fish) \
      --zsh <($out/bin/nmctl-pro completion zsh)

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

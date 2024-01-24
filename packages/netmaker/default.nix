{ lib
, fetchFromGitHub
, buildGoModule
, installShellFiles
, nix-update-script
, ...
}:
buildGoModule rec {
  pname = "netmaker";

  passthru.updateScript = nix-update-script { extraArgs = [ "--version=branch=develop" ]; };
  version = "unstable-2024-01-24";

  src = fetchFromGitHub {
    owner = "nazarewk";
    repo = "netmaker";
    rev = "c2f7a40024ab087ade019e82f2d6f797a894f282";
    hash = "sha256-P19fGDMFKjiR5LP1kQitTVMLKYiPs0z3ICZaIFfgRzQ=";
    postFetch = ''
      rm -r $out/pro
      rm $out/main_ee.go
    '';
  };
  vendorHash = "sha256-t7g6Tozq/QLq0/5bpXNDCJrOPTjMlvcDUaD6EGqII3Y=";

  subPackages = [ "." "cli" ];
  CGO_ENABLED = true;

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

  meta = {
    description = "WireGuard automation from homelab to enterprise - Community Edition";
    homepage = "https://netmaker.io";
    changelog = "https://github.com/gravitl/netmaker/-/releases/v${version}";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ urandom qjoly nazarewk ];
    mainProgram = "netmaker";
  };
}

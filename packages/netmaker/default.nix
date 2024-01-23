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
  version = "unstable-2024-01-23";

  src = fetchFromGitHub {
    owner = "nazarewk";
    repo = "netmaker";
    rev = "3dead4dcca5995b7c165538d7d6b432663eb5b54";
    hash = "sha256-MHbv0eFaeAs+8HX0GJH4ukA06IZveyPsVzxrDtX8RJE=";
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

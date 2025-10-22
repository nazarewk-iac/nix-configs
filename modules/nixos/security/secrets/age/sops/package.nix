{
  lib,
  src,
  vendorHash,
  buildGoModule,
  installShellFiles,
  nix-update-script,
  version ? "dev",
}:
buildGoModule rec {
  pname = "sops";
  inherit src version vendorHash;

  postPatch = ''
    substituteInPlace go.mod \
      --replace-fail "go 1.22" "go 1.22.7"
  '';

  subPackages = ["cmd/sops"];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/getsops/sops/v3/version.Version=${version}"
  ];

  passthru.updateScript = nix-update-script {};

  nativeBuildInputs = [installShellFiles];

  postInstall = ''
    installShellCompletion --cmd sops --bash ${./bash_autocomplete}
    installShellCompletion --cmd sops --zsh ${./zsh_autocomplete}
  '';

  meta = with lib; {
    homepage = "https://getsops.io/";
    description = "Simple and flexible tool for managing secrets";
    changelog = "https://github.com/getsops/sops/blob/v${version}/CHANGELOG.rst";
    mainProgram = "sops";
    maintainers = with maintainers; [
      Scrumplex
      mic92
    ];
    license = licenses.mpl20;
  };
}

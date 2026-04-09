{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  ...
}:
let
  version = "6.6";
  shortCommit = "7b3cc55";
  sha256 = "sha256-Tq780+Gsu2Ym9+DeMpaOhsP2XluyKBh01USnmwlYsTs=";
  vendorHash = "sha256-ilV/+Xogy4+5c/Rs0cCSvVTgDhL4mm9V/pxJB3XGDkw=";
  tag = "v${version}";
in
buildGoModule {
  pname = "klog-time-tracker";
  inherit version vendorHash;

  src = fetchFromGitHub {
    owner = "jotaen";
    repo = "klog";
    rev = tag;
    inherit sha256;
  };

  nativeBuildInputs = [ installShellFiles ];

  ldflags = [
    "-X"
    "main.BinaryVersion=${tag}"
    "-X"
    "main.BinaryBuildHash=${shortCommit}"
  ];

  postInstall = ''
    $out/bin/klog --help
    installShellCompletion --cmd klog \
      --bash <($out/bin/klog completion -c bash) \
      --fish <($out/bin/klog completion -c fish) \
      --zsh  <($out/bin/klog completion -c zsh)
  '';

  meta = with lib; {
    description = "A plain-text file format and a command line tool for time tracking";
    homepage = "https://klog.jotaen.net/";
    license = licenses.mit;
    mainProgram = "klog";
    maintainers = with maintainers; [ nazarewk ];
  };
}

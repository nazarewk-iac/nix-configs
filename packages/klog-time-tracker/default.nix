{ stdenv
, lib
, buildGoModule
, fetchFromGitHub
, installShellFiles
, buildPackages
, ...
}:
let
  version = "6.1";
  shortCommit = "cd1bf7c";
  sha256 = "sha256-I3IrzeK/zJNRs+JFyzcxaCgWdP5cvqXOSnP4in8kZKY=";
  vendorSha256 = "sha256-BDiVKrte1XIXJQkqj7GobPdHz74FgWMb/tNZChaaPCc=";
  tag = "v${version}";
in
buildGoModule {
  pname = "klog-time-tracker";
  inherit version vendorSha256;

  src = fetchFromGitHub {
    owner = "jotaen";
    repo = "klog";
    rev = tag;
    inherit sha256;
  };

  nativeBuildInputs = [ installShellFiles ];

  ldflags = [ "-X" "main.BinaryVersion=${tag}" "-X" "main.BinaryBuildHash=${shortCommit}" ];

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
    maintainers = with maintainers; [ nazarewk ];
  };
}

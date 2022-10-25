{ stdenv, lib, buildGoModule, fetchFromGitHub, installShellFiles, buildPackages }:
let
  version = "5.2";
  shortCommit = "61d0c8d";
  sha256 = "sha256-hlsxalYwD/5n6MO7yXqyZiDcWm8/q02G2GfL4Nn79Gk=";
  vendorSha256 = "sha256-VNPUpWuX7IoknTsBsLyJtWbFArR8bZ+RrzYT3lcHkEQ=";
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

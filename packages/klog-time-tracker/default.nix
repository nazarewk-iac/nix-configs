{
  stdenv,
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  buildPackages,
  ...
}: let
  version = "6.5";
  shortCommit = "6f2c7a1";
  sha256 = "sha256-xwVbI4rXtcZrnTvp0vdHMbYRoWCsxIuGZF922eC/sfw=";
  vendorHash = "sha256-QOS+D/zD5IlJBlb7vrOoHpP/7xS9En1/MFNwLSBrXOg=";
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

    nativeBuildInputs = [installShellFiles];

    ldflags = ["-X" "main.BinaryVersion=${tag}" "-X" "main.BinaryBuildHash=${shortCommit}"];

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
      maintainers = with maintainers; [nazarewk];
    };
  }

{
  stdenv,
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  buildPackages,
  ...
}: let
  version = "6.2";
  shortCommit = "a0e34b0";
  sha256 = "sha256-PFYPthrschw6XEf128L7yBygrVR3E3rtATCpxXGFRd4=";
  vendorHash = "sha256-X5xL/4blWjddJsHwwfLpGjHrfia1sttmmqHjaAIVXVo=";
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
      maintainers = with maintainers; [nazarewk];
    };
  }

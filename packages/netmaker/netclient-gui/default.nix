# TODO: add frontend build and enable the package
{ lib
, buildGoModule
, fetchFromGitHub
, libX11
, stdenv
, darwin
, installShellFiles
, ...
}:
let
  inputs = import ../inputs.nix { inherit fetchFromGitHub; };
in
buildGoModule rec {
  pname = "netclient-gui";
  inherit (inputs.netclient) version src vendorHash;

  buildInputs = lib.optional stdenv.isDarwin darwin.apple_sdk.frameworks.Cocoa
    ++ lib.optional stdenv.isLinux libX11;

  subPackages = [ "gui" ];

  hardeningEnabled = [ "pie" ];
  nativeBuildInputs = [
    installShellFiles
  ];

  postInstall = ''
    mv $out/bin/{gui,netclient-gui}

    installShellCompletion --cmd netclient-gui \
      --bash <($out/bin/netclient-gui completion bash) \
      --fish <($out/bin/netclient-gui completion fish) \
      --zsh <($out/bin/netclient-gui completion zsh)
  '';

  meta = with lib; {
    description = "Automated WireGuard® Management Client";
    homepage = "https://netmaker.io";
    changelog = "https://github.com/gravitl/netclient/releases/tag/v${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ wexder ];
    mainProgram = "netclient-gui";
  };
}

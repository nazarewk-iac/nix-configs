{
  lib,
  kdnConfig,
  extraRuntimeDeps ? [],
  srcDir ? kdnConfig.self + /tools/kdnctl,
  vendorHash ? "sha256-UG2vhlQLVVNR7qhwjETLwmxL/tXjCAu4abWEaHX12ZQ=",
  buildGoModule,
  installShellFiles,
  makeBinaryWrapper,
  pass,
  nixos-anywhere,
  openssh,
  ssh-to-age,
  ...
}: let
  runtimeDeps =
    [
      nixos-anywhere
      openssh
      pass
      ssh-to-age
    ]
    ++ extraRuntimeDeps;
in
  buildGoModule (finalAttrs: {
    pname = "kdnctl";
    version = "0.0.1";
    meta.mainProgram = "kdnctl";

    src = lib.sourceByRegex srcDir [
      "^go\.(mod|sum)$"
      "^[^.]+$"
      ".*\.go$"
    ];

    inherit vendorHash;

    nativeBuildInputs = [
      installShellFiles
      makeBinaryWrapper
    ];

    subPackages = ["."];

    postInstall = ''
      installShellCompletion --cmd ${finalAttrs.meta.mainProgram} \
        --bash <("$out/bin/${finalAttrs.meta.mainProgram}" completion bash) \
        --fish <("$out/bin/${finalAttrs.meta.mainProgram}" completion fish) \
        --zsh <("$out/bin/${finalAttrs.meta.mainProgram}" completion zsh)
    '';

    postFixup = ''
      wrapProgram "$out/bin/${finalAttrs.meta.mainProgram}" \
        --prefix PATH : ${lib.strings.escapeShellArg (lib.makeBinPath runtimeDeps)}
    '';
  })

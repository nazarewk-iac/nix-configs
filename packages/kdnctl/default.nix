{
  lib,
  kdnConfig,
  extraRuntimeDeps ? [],
  srcDir ? kdnConfig.self + /tools/kdnctl,
  vendorHash ? "sha256-cz5tU1L217sgHpYHxtpgY2r+XAp9D0J8p3C5EdtMO/w=",
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
      pass
      nixos-anywhere
      openssh
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

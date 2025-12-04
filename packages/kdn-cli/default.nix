{
  lib,
  extraRuntimeDeps ? [],
  srcDir ? kdnConfig.self + /tools/kdn-cli,
  vendorHash ? "sha256-+odivU7SrUJbHGzWIOBGq7rhw/KrnzHJWTUepWnj++s=",
  buildGoModule,
  installShellFiles,
  makeBinaryWrapper,
  kdnConfig,
  ...
}: let
  runtimeDeps =
    [
      # age
    ]
    ++ extraRuntimeDeps;
in
  buildGoModule (finalAttrs: {
    pname = "kdn-cli";
    version = "0.0.1";
    meta.mainProgram = "kdn";

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

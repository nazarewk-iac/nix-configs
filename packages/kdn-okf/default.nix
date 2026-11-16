# The `kdn-okf` CLI and TUI. It indexes an Open Knowledge Format v0.2 bundle, exposes the concept
# list, the link graph, trust and freshness as JSON, and browses the same model in a TUI.
#
# The package is self-contained under this directory. It follows `packages/kdn-journal/`:
# `buildGoModule`, a filtered source, shell completions, and a second `buildGoModule` in
# `passthru.tests` for the Go suite.
{
  lib,
  buildGoModule,
  installShellFiles,
  makeBinaryWrapper,
  ...
}:
let
  src = lib.sourceByRegex ./. [
    ''^go\.(mod|sum)$''
    "^[^.]+$"
    ''.*\.go$''
    ''.*\.md$''
  ];

  # Filled after the first build with `nix build .#kdn-okf`.
  vendorHash = "sha256-vPIFAZsoV/YZWdZ50DolbOYKqJJrODhAyKvwmil84HA=";
in
buildGoModule (finalAttrs: {
  pname = "kdn-okf";
  version = "0.1.0";

  inherit src vendorHash;

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ];

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${finalAttrs.version}"
  ];

  postInstall = ''
    install -Dm644 skill.md "$out/share/${finalAttrs.meta.mainProgram}/skill/SKILL.md"
    installShellCompletion --cmd ${finalAttrs.meta.mainProgram} \
      --bash <("$out/bin/${finalAttrs.meta.mainProgram}" completion bash) \
      --fish <("$out/bin/${finalAttrs.meta.mainProgram}" completion fish) \
      --zsh <("$out/bin/${finalAttrs.meta.mainProgram}" completion zsh)
  '';

  postFixup = ''
    wrapProgram "$out/bin/${finalAttrs.meta.mainProgram}" \
      --set CI 1 \
      --set KDN_OKF_NO_OSC 1
  '';

  passthru.tests.go-test = buildGoModule {
    pname = "kdn-okf-go-test";
    version = "0.1.0";

    inherit src vendorHash;

    doCheck = true;
    installPhase = ''
      touch "$out"
    '';
  };

  meta = {
    description = "Index, search and browse Open Knowledge Format v0.2 bundles (CLI + TUI)";
    mainProgram = "kdn-okf";
  };
})

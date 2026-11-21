# The `kdn-knowledge` CLI. It turns finished agent sessions into short, deduplicated knowledge
# and skill proposals, running only on the local model fleet.
#
# The package is self-contained under this directory. It follows `packages/kdn-okf/`:
# `buildGoModule`, a filtered source, shell completions, and a second `buildGoModule` in
# `passthru.tests` for the Go suite.
#
# The binary reads SQLite through the `sqlite3` CLI (the standard library has no driver), so the
# wrapper puts sqlite on PATH. `okf-memory`, `okflint` and `kdn-okf` stay optional: `apply` uses
# them when they are on PATH and falls back to direct writing with a warning when they are not.
{
  lib,
  buildGoModule,
  installShellFiles,
  makeBinaryWrapper,
  sqlite,
  ...
}:
let
  src = lib.sourceByRegex ./. [
    ''^go\.(mod|sum)$''
    "^[^.]+$"
    ''.*\.go$''
  ];
in
buildGoModule (finalAttrs: {
  pname = "kdn-knowledge";
  version = "0.1.0";

  inherit src;

  # No third-party module: the tool is standard library only.
  vendorHash = null;

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ];

  # The fixture tests create a SQLite database with the sqlite3 CLI.
  nativeCheckInputs = [ sqlite ];

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${finalAttrs.version}"
  ];

  postInstall = ''
    installShellCompletion --cmd ${finalAttrs.meta.mainProgram} \
      --bash <("$out/bin/${finalAttrs.meta.mainProgram}" completion bash) \
      --fish <("$out/bin/${finalAttrs.meta.mainProgram}" completion fish) \
      --zsh <("$out/bin/${finalAttrs.meta.mainProgram}" completion zsh)
  '';

  postFixup = ''
    wrapProgram "$out/bin/${finalAttrs.meta.mainProgram}" \
      --prefix PATH : ${lib.makeBinPath [ sqlite ]}
  '';

  passthru.tests.go-test = buildGoModule {
    pname = "kdn-knowledge-go-test";
    version = "0.1.0";

    inherit src;
    vendorHash = null;

    nativeCheckInputs = [ sqlite ];

    doCheck = true;
    installPhase = ''
      touch "$out"
    '';
  };

  meta = {
    description = "Distil agent sessions into reviewable knowledge and skill proposals";
    mainProgram = "kdn-knowledge";
  };
})

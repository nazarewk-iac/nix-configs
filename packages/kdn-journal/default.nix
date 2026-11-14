# The `kdn-journal` CLI. It reads docs/tasks and .cache/agents, prints a compact summary of where
# the work stands, and browses tasks, boards and worklogs in a TUI.
#
# The package is self-contained under this directory, so an external adopter can reuse it. It
# follows `packages/kdn-certs/`: `buildGoModule`, a filtered source, shell completions, and a
# second `buildGoModule` in `passthru.tests` for the Go suite.
#
# Tests use string fixtures, not `testdata/`, so the source filter keeps only Go files. The
# integration test skips when `docs/tasks` is absent, which is the case in the Nix sandbox; the
# `kdn-journal-parse` check copies the task tree into the sandbox instead.
{
  lib,
  buildGoModule,
  installShellFiles,
  ...
}:
let
  src = lib.sourceByRegex ./. [
    ''^go\.(mod|sum)$''
    "^[^.]+$"
    ''.*\.go$''
  ];

  # Filled after the first build with `nix build .#kdn-journal`.
  vendorHash = "sha256-vPIFAZsoV/YZWdZ50DolbOYKqJJrODhAyKvwmil84HA=";
in
buildGoModule (finalAttrs: {
  pname = "kdn-journal";
  version = "0.1.0";

  inherit src vendorHash;

  nativeBuildInputs = [ installShellFiles ];

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

  passthru.tests.go-test = buildGoModule {
    pname = "kdn-journal-go-test";
    version = "0.1.0";

    inherit src vendorHash;

    doCheck = true;
    installPhase = ''
      touch "$out"
    '';
  };

  meta = {
    description = "Browse repository tasks and agent journals (CLI + TUI)";
    mainProgram = "kdn-journal";
  };
})

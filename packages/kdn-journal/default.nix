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

  # Filled after the first build with `nix build .#kdn-journal`.
  vendorHash = "sha256-vPIFAZsoV/YZWdZ50DolbOYKqJJrODhAyKvwmil84HA=";
in
buildGoModule (finalAttrs: {
  pname = "kdn-journal";
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

  # Bubble Tea v1 calls lipgloss.HasDarkBackground() in its package init. termenv skips that
  # terminal query when CI is set, so the wrapper sets CI=1 for the process start; main() unsets
  # it again before the CLI runs. Without this, `kdn-journal version` sends OSC 11 and a terminal
  # that answers late prints the response into the shell.
  postFixup = ''
    wrapProgram "$out/bin/${finalAttrs.meta.mainProgram}" \
      --set CI 1 \
      --set KDN_JOURNAL_NO_OSC 1
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

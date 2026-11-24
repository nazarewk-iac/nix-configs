# The `kdn-audio` CLI and TUI. It joins several audio outputs into one virtual output through the
# PipeWire graph, lists the joined outputs, removes them again, and applies a stored profile
# whenever a given mix of devices is connected.
#
# The package is self-contained under this directory. It follows `packages/kdn-journal/`:
# `buildGoModule`, a filtered source, shell completions, and a second `buildGoModule` in
# `passthru.tests` for the Go suite.
#
# The tool drives the PipeWire tools and transient systemd user units at run time, so the wrapper
# puts `pw-dump`, `pw-cli`, `pw-link`, `pw-metadata`, `systemd-run`, `systemctl` and `bluetoothctl`
# on its PATH. A systemd unit starts with a minimal PATH, and `kdn-audio daemon` is such a unit.
{
  lib,
  buildGoModule,
  installShellFiles,
  makeBinaryWrapper,
  pipewire,
  systemd,
  bluez,
  ...
}:
let
  src = lib.sourceByRegex ./. [
    ''^go\.(mod|sum)$''
    "^[^.]+$"
    ''.*\.go$''
  ];

  # Filled after the first build with `nix build .#kdn-audio`.
  vendorHash = "sha256-NL2FRY/V4WqKFtEM+6e15m+rnO/acm073VURUD5KtY4=";

  runtimeDeps = [
    pipewire
    systemd
    bluez
  ];
in
buildGoModule (finalAttrs: {
  pname = "kdn-audio";
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
    installShellCompletion --cmd ${finalAttrs.meta.mainProgram} \
      --bash <("$out/bin/${finalAttrs.meta.mainProgram}" completion bash) \
      --fish <("$out/bin/${finalAttrs.meta.mainProgram}" completion fish) \
      --zsh <("$out/bin/${finalAttrs.meta.mainProgram}" completion zsh)
  '';

  # Bubble Tea v1 calls lipgloss.HasDarkBackground() in its package init. termenv skips that
  # terminal query when CI is set, so the wrapper sets CI=1 for the process start; main() unsets
  # it again before the CLI runs. Without this, `kdn-audio devices` sends OSC 11 and a terminal
  # that answers late prints the response into the shell.
  postFixup = ''
    wrapProgram "$out/bin/${finalAttrs.meta.mainProgram}" \
      --set CI 1 \
      --set KDN_AUDIO_NO_OSC 1 \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
  '';

  passthru.tests.go-test = buildGoModule {
    pname = "kdn-audio-go-test";
    version = "0.1.0";

    inherit src vendorHash;

    doCheck = true;
    installPhase = ''
      touch "$out"
    '';
  };

  meta = {
    description = "Join several audio outputs into one virtual output (CLI + TUI)";
    mainProgram = "kdn-audio";
  };
})

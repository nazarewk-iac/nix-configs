# The inference serving runtime: one engine per card, a profile manager on :8181, a per-entry proxy
# that keeps a request alive across a profile switch, and the CLI that drives them.
#
# Standard library only, so there is no `go.sum` and `vendorHash` is null. Tests use `httptest` and a
# fake engine script; the second `buildGoModule` in `passthru.tests` runs them under the Nix sandbox,
# and the drain probes in `hack/probe-drain-*.py` are the acceptance suite against a live host.
{
  lib,
  buildGoModule,
  ...
}:
let
  src = lib.sourceByRegex ./. [
    ''^go\.(mod|sum)$''
    "^[^.]+$"
    ''.*\.go$''
    ''.*\.md$''
  ];
in
buildGoModule (finalAttrs: {
  pname = "kdn-inference-helpers";
  version = "0.1.0";

  inherit src;
  vendorHash = null;

  subPackages = [ "cmd/kdn-inference-helpers" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${finalAttrs.version}"
  ];

  passthru.tests.go-test = buildGoModule {
    pname = "kdn-inference-helpers-go-test";
    version = "0.1.0";

    inherit src;
    vendorHash = null;

    doCheck = true;
    installPhase = ''
      touch "$out"
    '';
  };

  meta = {
    description = "The inference serving runtime: profile manager, per-entry proxy and CLI";
    mainProgram = "kdn-inference-helpers";
  };
})

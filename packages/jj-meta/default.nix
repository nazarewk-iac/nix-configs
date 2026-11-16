# The `jj-meta` CLI. It attributes a jj change to the agent session that produced it: it appends
# the missing `Assisted-by`, `Generated-by`, `Session-Id`, `Harness` and `Model` trailers to a
# mutable change, deduplicates them, and never deletes or rewrites existing metadata.
#
# The package is self-contained under this directory, so an external adopter can reuse it. It
# follows `packages/kdn-journal/`: `buildGoModule`, a filtered source, shell completions, and a
# second `buildGoModule` in `passthru.tests` for the Go suite.
#
# The suite needs no jj and no repository: the jj runner sits behind an interface. The two
# integration cases skip when `jj` is absent, which is the case in the Nix sandbox; the
# `jj-meta-attribute` check runs the real binary against a temporary repository instead.
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

  # Filled after the first build with `nix build .#jj-meta`.
  vendorHash = "sha256-7K17JaXFsjf163g5PXCb5ng2gYdotnZ2IDKk8KFjNj0=";
in
buildGoModule (finalAttrs: {
  pname = "jj-meta";
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
    pname = "jj-meta-go-test";
    version = "0.1.0";

    inherit src vendorHash;

    doCheck = true;
    installPhase = ''
      touch "$out"
    '';
  };

  meta = {
    description = "Attribute jj changes to the agent session that produced them";
    mainProgram = "jj-meta";
  };
})

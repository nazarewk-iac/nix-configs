# The `kdn-certs` CLI. It walks the certificate declarations of a flake, deduplicates them, and
# drives smallstep to generate and rotate them.
#
# The package is self-contained under this directory, so an external adopter can reuse it. It follows
# `packages/kdn-ssh-access/` (self-contained source, no `kdnConfig` dependency) and
# `packages/kdnctl/` (the cobra + charmbracelet stack).
#
# `buildGoModule` wraps the binary with `makeBinaryWrapper`, so `step`, `step-ca`, `nix` and `sops`
# are on the runtime PATH. `postInstall` installs the shell completions from
# `kdn-certs completion <shell>`.
#
# `passthru.tests.go-test` runs the Go suite. It is a second `buildGoModule` over the same source,
# with `doCheck = true` and an `installPhase` that only touches `$out`. The suite mocks the `nix eval`
# and the `step` call behind an interface, so it needs no flake, no CA and no network.
{
  lib,
  buildGoModule,
  makeBinaryWrapper,
  installShellFiles,
  step-cli,
  step-ca,
  nix,
  sops,
  ...
}:
let
  runtimeDeps = [
    step-cli
    step-ca
    nix
    sops
  ];

  # `^[^.]+$` keeps each top-level directory (`cmd`, `internal`), so `cleanSourceWith` descends into
  # it. A per-directory pattern such as `^internal/.*\.go$` alone would prune the `internal/dag`
  # directory, because the directory name matches no pattern. `.*\.go$` then keeps every Go file at
  # any depth. This is the shape `packages/kdnctl/default.nix` uses.
  src = lib.sourceByRegex ./. [
    ''^go\.(mod|sum)$''
    "^[^.]+$"
    ''.*\.go$''
  ];

  # Filled after the first build with `nix build .#kdn-certs`.
  vendorHash = "sha256-IxYf6IDDLYRlbGY2R+wvsD7MTWdOUJh1PcKinLgvv4s=";
in
buildGoModule (finalAttrs: {
  pname = "kdn-certs";
  version = "0.0.1";

  inherit src vendorHash;

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ];

  subPackages = [ "." ];

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

  passthru.tests.go-test = buildGoModule {
    pname = "kdn-certs-go-test";
    version = "0.0.1";

    inherit src vendorHash;

    # `doCheck = true` runs `go test ./...` in the check phase. The install phase only touches the
    # output, because the test result is the whole product.
    doCheck = true;
    installPhase = ''
      touch "$out"
    '';
  };

  meta = {
    description = "Declarative certificate manager: walk declarations, dedup, drive smallstep";
    mainProgram = "kdn-certs";
  };
})

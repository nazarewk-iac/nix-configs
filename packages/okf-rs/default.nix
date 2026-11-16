# `okf-rs`: the pure-Rust OKF v0.2 toolkit. It validates, lints, graphs, diffs and, most
# importantly, refactors a bundle without breaking links (`mv`, `rm`, `split`, `merge`).
#
# Upstream calls the binary `okf`. This package installs it as `okf-rs`, because a bare `okf`
# reads like the format or the memory tool, and `okf-agent-memory` upstream also uses that name.
#
# The workspace also holds the library crates, the studio and the cargo plugin. Only the `okf`
# crate is built.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "okf-rs";
  version = "0.2.7";

  src = fetchFromGitHub {
    owner = "W4G1";
    repo = "okf";
    rev = "v0.2.7";
    hash = "sha256-gBj89WCoZyQsBduDZqxu7ayWERTR0Z/ObJI6uzpw2EE=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";
  useFetchCargoVendor = true;

  cargoBuildFlags = [
    "--package"
    "okf"
  ];
  cargoTestFlags = [
    "--package"
    "okf"
  ];

  postInstall = ''
    mv "$out/bin/okf" "$out/bin/okf-rs"
  '';

  meta = {
    description = "Pure-Rust OKF v0.2 toolkit: validate, lint, graph and link-safe refactors";
    homepage = "https://github.com/W4G1/okf";
    license = lib.licenses.asl20;
    mainProgram = "okf-rs";
  };
}

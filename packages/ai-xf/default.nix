# The AI-XF reference tools: a conformance validator and a canonicaliser for the AI-XF format,
# a strict superset of OKF v0.2 with stable ids, typed links, media identity and federation.
#
# The validator is a single Python file with no required dependencies; the canonicaliser needs
# PyYAML. Both run from the pinned v0.5 tag.
{
  lib,
  stdenv,
  fetchFromGitHub,
  python3,
}:
stdenv.mkDerivation rec {
  pname = "ai-xf";
  version = "0.5";

  src = fetchFromGitHub {
    owner = "DavidROliverBA";
    repo = "ai-xf-format";
    rev = "v${version}";
    hash = "sha256-eTzxFO7kNe/k7ygzSAD8YLM5OQX9UM1Eu5lJsJyLybw=";
  };

  nativeBuildInputs = [
    (python3.withPackages (ps: [ ps.pyyaml ]))
  ];

  dontBuild = true;

  installPhase = ''
    install -Dm755 tools/ai-xf-validate.py "$out/bin/ai-xf-validate"
    install -Dm755 tools/ai-xf-canon.py "$out/bin/ai-xf-canon"
    # Upstream ships `#!/usr/bin/env python3`. Point it at the Python that carries PyYAML,
    # because the canonicaliser imports it.
    patchShebangs "$out/bin"
  '';

  meta = {
    description = "AI-XF conformance validator and canonicaliser (OKF v0.2 superset)";
    mainProgram = "ai-xf-validate";
  };
}

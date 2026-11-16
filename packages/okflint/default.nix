# `okflint`: a deterministic compliance linter for OKF documentary bases. It checks a bundle
# against a manifest that declares the concept types, their required fields and the status
# vocabulary. `validate` is the gate; `audit` is the descriptive report.
#
# Not in nixpkgs. The tool is pre-1.0, so the version is pinned. The manifest for the memory
# bundle lives at `.agents/knowledge/okf-base.yaml`.
{
  lib,
  python3,
  fetchFromGitHub,
}:
python3.pkgs.buildPythonApplication {
  pname = "okflint";
  version = "0.5.1";

  src = fetchFromGitHub {
    owner = "mattdav";
    repo = "okflint";
    rev = "v0.5.1";
    hash = "sha256-+56XMaRoL4y2rVSFHrZipnjEJkWmdfknZHIPyGGaDXg=";
  };

  pyproject = true;

  nativeBuildInputs = [ python3.pkgs.hatchling ];

  dependencies = with python3.pkgs; [
    beartype
    pyyaml
  ];

  pythonImportsCheck = [ "okflint" ];

  meta = {
    description = "Deterministic compliance linter for OKF documentary bases";
    homepage = "https://github.com/mattdav/okflint";
    license = lib.licenses.mit;
    mainProgram = "okflint";
  };
}

# `okf-guard`: a content-safety scanner for OKF generation pipelines. It inspects raw source
# documents (text, PDF, Word, PowerPoint, spreadsheets, HTML) for hidden content and
# prompt-injection patterns before that content reaches a trusted knowledge bundle.
#
# Not in nixpkgs. The tool is pre-1.0, so the version is pinned.
#
# `pdfplumber` is built with `doCheck = false`. Its test inputs pull pandas, jupyterlab,
# pandas-stubs and geopandas, and geopandas 1.1.4 fails 10 of its own tests against the newer
# pyarrow and shapely in nixpkgs. The failure is in geopandas' test suite, not in the build, and
# none of those packages is a runtime dependency of pdfplumber. Skipping the tests keeps the PDF
# adapter working without dragging a broken test dependency into the closure.
{
  lib,
  python3,
  fetchFromGitHub,
}:
let
  pdfplumber = python3.pkgs.pdfplumber.overridePythonAttrs (_: {
    doCheck = false;
  });
in
python3.pkgs.buildPythonApplication {
  pname = "okf-guard";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "darshanNhb";
    repo = "okf-guard";
    rev = "v0.1.0";
    hash = "sha256-Me2XAQ9n1KOaoBo5Eg0WAOsfsxPD3l58JY1gcWjH/7A=";
  };

  pyproject = true;

  # Upstream ships `.gitignore` as UTF-16 with a BOM. Hatchling reads it as UTF-8 while it
  # collects VCS exclusion patterns and crashes. The tarball has no VCS metadata anyway, so a
  # plain UTF-8 file with the same intent is enough.
  postPatch = ''
    printf '%s\n' '__pycache__/' '*.pyc' > .gitignore
  '';

  nativeBuildInputs = [ python3.pkgs.hatchling ];

  dependencies = with python3.pkgs; [
    pyyaml
    pdfplumber
    python-docx
    python-pptx
    openpyxl
    beautifulsoup4
    lxml
  ];

  pythonImportsCheck = [ "okfguard" ];

  meta = {
    description = "Content-safety scanner for OKF pipelines: hidden content and prompt injection";
    homepage = "https://github.com/darshanNhb/okf-guard";
    license = lib.licenses.asl20;
    mainProgram = "okfguard";
  };
}

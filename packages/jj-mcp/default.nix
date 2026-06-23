{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  jujutsu,
  makeWrapper,
}:
buildNpmPackage {
  pname = "jj-mcp";
  version = "0-unstable-2026-05-25";

  src = fetchFromGitHub {
    owner = "kmarxican";
    repo = "jj-mcp";
    rev = "c779114b6142f75dc2f0689eab0e4ba514524ef0";
    hash = "sha256-QVVGNn8iE7WrYFbhwgWyUE9YQWBUWacJSSz4ifjaowQ=";
  };

  npmDepsHash = "sha256-U1fn6nAj8QIxZs2kfLj5Y5folulcfwxNfM5uh04j020=";

  # upstream has no package-lock.json; vendored copy lives next to this file
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/jj-mcp \
      --prefix PATH : ${lib.makeBinPath [ jujutsu ]}
  '';

  meta = {
    description = "MCP server for the Jujutsu (jj) version control system";
    homepage = "https://github.com/kmarxican/jj-mcp";
    license = lib.licenses.mit;
    mainProgram = "jj-mcp";
  };
}

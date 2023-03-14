{ lib, stdenv, rustPlatform, fetchFromGitHub, shared-mime-info, libiconv, installShellFiles, ... }:
rustPlatform.buildRustPackage rec {
  pname = "handlr-regex";
  version = "unstable-2023-03-09";

  src = fetchFromGitHub {
    owner = "Anomalocaridid";
    repo = "handlr-regex";
    rev = "e7430fe930e6d70bc6ea5cc2a3ad8546e396b38e";
    sha256 = "sha256-WWC+Z1LqfGKPtFKIocfBpVWJMg+igmt3u+yS+lIj1G4=";
  };

  cargoSha256 = "sha256-86R00/VtiKaW0GQ1iOuCJW3phG1XxNl97+13QJ+ebIk=";

  nativeBuildInputs = [ installShellFiles shared-mime-info ];
  buildInputs = lib.optionals stdenv.isDarwin [ libiconv ];

  preCheck = ''
    export HOME=$TEMPDIR
  '';

  # completions are not available for handlr-regex
  #postInstall = ''
  #  installShellCompletion \
  #    --zsh   completions/_handlr \
  #    --bash  completions/handlr \
  #    --fish  completions/handlr.fish
  #'';

  meta = with lib; {
    description = "Alternative to xdg-open to manage default applications with ease";
    homepage = "https://github.com/Anomalocaridid/handlr-regex";
    license = licenses.mit;
    maintainers = with maintainers; [ nazarewk ];
  };
}

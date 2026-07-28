{
  lib,
  fetchFromGitHub,
  rustPlatform,
  installShellFiles,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "kagi-cli";
  version = "0.16.0";
  src = fetchFromGitHub {
    owner = "Microck";
    repo = "kagi-cli";
    rev = "v${finalAttrs.version}";
    hash = "sha256-NMUxqhUi66hzcD0BWtw5boFWQWDo3sI0PLwaqKhEhGY=";
  };

  cargoHash = "sha256-82Lha5XdzNUA3pejbC5M8WsO7oIp0AqeR+/2eIsV59U=";
  # reqwest is configured with `rustls-tls` so no system OpenSSL is required.
  # If a future version switches back to native-tls, add:
  #   nativeBuildInputs = [ pkg-config ];
  #   buildInputs = [ openssl ];

  doCheck = false;
  checkFlags = [
    # requires VS Code / Roo Code to be installed, not available in the build sandbox
    "--skip=mcp_install_writes_vs_code_user_config_without_client_cli"
    "--skip=mcp_install_writes_roo_code_extension_config"
  ];

  nativeBuildInputs = [
    installShellFiles
  ];
  postInstall = ''
     gen() { "$out/bin/${finalAttrs.meta.mainProgram}" completion generate "$@" ; }
     installShellCompletion --cmd ${finalAttrs.meta.mainProgram} \
       --bash <(gen bash) \
       --fish <(gen fish) \
       --zsh <(gen zsh)
  '';

  meta = with lib; {
    description = "Agent-native CLI for Kagi subscribers with JSON-first search output";
    homepage = "https://github.com/Microck/kagi-cli";
    license = licenses.mit;
    mainProgram = "kagi";
    maintainers = [ ]; # add yourself here
    platforms = platforms.unix;
  };
})

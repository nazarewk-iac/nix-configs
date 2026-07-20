{
  lib,
  buildGoModule,
  fetchFromGitHub,
  ...
}:
buildGoModule {
  pname = "mcpsnoop";
  version = "0.12.0";

  src = fetchFromGitHub {
    owner = "kerlenton";
    repo = "mcpsnoop";
    rev = "v0.12.0";
    hash = "sha256-kl5AKeyzUsFwbAuLyZFkRczk7ad0cd53vUNEhV35jWY=";
  };

  vendorHash = "sha256-qlRkHePdxxtsEfgOm+xUJA+D8hYO2oJOaGu4TYU4WF4=";

  meta = {
    description = "Transparent MCP proxy for debugging JSON-RPC traffic between AI clients and MCP servers";
    homepage = "https://github.com/kerlenton/mcpsnoop";
    license = lib.licenses.mit;
    mainProgram = "mcpsnoop";
  };
}

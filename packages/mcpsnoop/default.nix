{
  lib,
  buildGoModule,
  fetchFromGitHub,
  ...
}:
buildGoModule {
  pname = "mcpsnoop";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "kerlenton";
    repo = "mcpsnoop";
    rev = "v0.1.1";
    hash = "sha256-29KMc8MwAnIErZ2PjAhzqIC1s68sx5q4TfgakgAVRhA=";
  };

  vendorHash = "sha256-P3iFBhlDRS+bTfGRwy2bTPmi83HgIOMPKI364SRUouI=";

  meta = {
    description = "Transparent MCP proxy for debugging JSON-RPC traffic between AI clients and MCP servers";
    homepage = "https://github.com/kerlenton/mcpsnoop";
    license = lib.licenses.mit;
    mainProgram = "mcpsnoop";
  };
}

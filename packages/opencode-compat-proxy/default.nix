{
  lib,
  python3,
  fetchFromGitHub,
  applyPatches,
}:
let
  py = python3.withPackages (
    ps: with ps; [
      fastapi
      httpx
      uvicorn
    ]
  );
in
python3.pkgs.buildPythonApplication {
  pname = "opencode-compat-proxy";
  version = "unstable-2026-07-01";
  format = "other";

  src = applyPatches {
    src = fetchFromGitHub {
      owner = "ladiossoop5star";
      repo = "opencode_compat_proxy";
      rev = "1ae3a3d65289541555160b4590936705f5dd9ab9";
      hash = "sha256-UdCHABshTLF782SdhJEypiCuu3nxk8HCTfJ1m7TIapk=";
    };
    patches = [ ./patches/forward-auth.patch ];
  };

  nativeBuildInputs = [ py ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin

    # proxy.py reads its deps from the global interpreter; ship it on the
    # path of the python-with-packages env.
    cp $src/proxy.py $out/lib/proxy.py

    cat > $out/bin/opencode-compat-proxy <<EOF
    #!${py}/bin/python3
    import os
    import sys

    sys.path.insert(0, "$out/lib")

    import proxy

    if __name__ == "__main__":
        import uvicorn

        uvicorn.run(
            proxy.app,
            host=os.environ.get("PROXY_HOST", "127.0.0.1"),
            port=int(os.environ.get("PROXY_PORT", "9526")),
        )
    EOF
    chmod +x $out/bin/opencode-compat-proxy

    runHook postInstall
  '';

  meta = with lib; {
    description = "OpenAI-compatible proxy translating DeepSeek DSML and Qwen XML tool calls for OpenCode";
    homepage = "https://github.com/ladiossoop5star/opencode_compat_proxy";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "opencode-compat-proxy";
  };
}

{
  lib,
  python3,
  __inputs__ ? { },
}:
let
  # The source is the nazarewk-iac fork of the upstream project. The fork's
  # `main` already carries the patches this repo used to apply by hand
  # (Authorization forwarding, per-model router routing, and streaming usage).
  # `flake.nix` declares it as a `flake = false` input named
  # `opencode-compat-proxy`; the fork has no flake.nix of its own.
  inputs = __inputs__.inputs or { };
  src =
    inputs.opencode-compat-proxy
      or (throw "opencode-compat-proxy requires the `opencode-compat-proxy` flake input");

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
  version = "unstable-2026-10-08";
  format = "other";

  inherit src;

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
    homepage = "https://github.com/nazarewk-iac/opencode_compat_proxy";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "opencode-compat-proxy";
  };
}

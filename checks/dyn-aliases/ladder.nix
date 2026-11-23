# The `dyn-*` residency ladder in `hosts/etra/litellm_resident.py`, driven with fake deployments.
#
# The module imports LiteLLM's `CustomLogger`, so the test injects a stub module before the import:
# the check must not pull LiteLLM's dependency tree for five assertions about the ladder. `fastapi`
# is real and small, so the 409 is the exception type LiteLLM itself raises.
{
  pkgs,
  ...
}:
pkgs.runCommand "check-dyn-aliases-ladder"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (ps: [
        ps.pytest
        ps.fastapi
      ]))
    ];
  }
  ''
    export HOME="$TMPDIR"
    export PYTHONDONTWRITEBYTECODE=1
    cd "$TMPDIR"
    cp ${./test_resident.py} test_resident.py
    cp ${../../hosts/etra/litellm_resident.py} litellm_resident.py
    pytest -q test_resident.py
    touch "$out"
  ''

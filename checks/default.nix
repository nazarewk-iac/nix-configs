{
  pkgs,
  lib,
  ...
}:
{
  # Minimal "hello world" check: proves the `checks.<system>` plumbing evaluates and
  # builds end-to-end (flake.nix mkSubmodule wiring + checks/default.nix), independent
  # of the heavier pytest checks whose sandbox behaviour still needs verifying.
  hello = pkgs.runCommand "check-hello" { } ''
    echo "hello world"
    touch $out
  '';

  kdn-slug-pytest = pkgs.kdn.kdn-slug.passthru.tests.pytest;
  zellij-llm-pytest = pkgs.kdn.zellij-llm.passthru.tests.pytest;
}

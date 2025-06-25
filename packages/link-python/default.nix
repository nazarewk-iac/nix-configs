{
  pkgs,
  lib,
  __inputs__,
  ...
}:
pkgs.writeShellApplication {
  name = "kdn-link-python";
  runtimeInputs = with pkgs; [
    coreutils
    git
    nix-output-monitor
  ];
  text = ''
    if test $# == 0 ; then
      cat <<'EOF'
    Usage
    EOF
    fi
    for name in "$@" ; do
      ln -sfT "$(nom build --no-link --print-out-paths ".#''${name}.devEnv")/bin/python" "$(git rev-parse --show-toplevel)/packages/''${name}/python"
    done
  '';
}

{
  pkgs,
  lib,
  ...
}:
pkgs.writeShellApplication {
  name = "kdn-link-python";
  runtimeInputs = with pkgs; [
    coreutils
    git
    gnugrep
    gnused
    nix-output-monitor
  ];
  text = builtins.readFile ./link-python.sh;
}

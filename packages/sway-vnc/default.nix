{
  lib,
  pkgs,
  ...
}:
pkgs.writeShellApplication {
  name = "sway-vnc";
  runtimeInputs = with pkgs; [
    wayvnc
    jq
    sway
    coreutils
    findutils
  ];
  text = builtins.readFile ./sway-vnc.sh;
}

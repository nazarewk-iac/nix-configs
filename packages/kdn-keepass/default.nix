{ lib, pkgs }:
pkgs.writeShellApplication {
  name = "kdn-keepass";
  runtimeInputs = with pkgs; [ pass keepassxc ];
  text = builtins.readFile ./kdn-keepass.sh;
}

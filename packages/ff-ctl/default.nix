{ pkgs, lib, ... }:
let in
pkgs.writers.writePython3Bin "ff-ctl"
{
  libraries = with pkgs.python3Packages; [
    fire
  ];
  flakeIgnore = [
    "E501" # line too long
  ];
}
  (builtins.readFile ./ff-ctl.py)

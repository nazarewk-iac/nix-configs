{ pkgs, lib, ... }:
let in
pkgs.writers.writePython3Bin "gpg-smartcard-reset-keys"
{
  flakeIgnore = [
  ];
}
  (builtins.readFile ./gpg-smartcard-reset-keys.py)

{
  pkgs,
  lib,
  ...
}: let
in
  pkgs.writers.writePython3Bin "gpg-smartcard-reset-keys"
  {
    makeWrapperArgs = builtins.concatLists [
      ["--prefix" "PATH" ":" (lib.makeBinPath (with pkgs; [gnupg]))]
    ];
  }
  (builtins.readFile ./gpg-smartcard-reset-keys.py)

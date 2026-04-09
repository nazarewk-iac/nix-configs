{
  pkgs,
  lib,
}:
let
  source = lib.pipe ./kdn-anonymize.py [
    builtins.readFile
    (lib.strings.splitString "\n")
    # drop shebang so the validator doesn't complain about: E265 block comment should start with '# '
    builtins.tail
    (builtins.concatStringsSep "\n")
  ];
in
pkgs.writers.writePython3Bin "kdn-anonymize" { } source

{lib, ...}: let
  authorizedKeysPath = ./.ssh/authorized_keys;
  authorizedKeysList = lib.trivial.pipe authorizedKeysPath [
    builtins.readFile
    (lib.strings.splitString "\n")
  ];
in {
  inherit authorizedKeysList authorizedKeysPath;

  authorizedKeysText = builtins.concatStringsSep "\n" authorizedKeysList;
}

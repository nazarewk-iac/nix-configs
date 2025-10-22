{pkgs, ...}:
pkgs.writers.writePython3Bin "git-credential-keyring" {
  libraries = with pkgs.python3Packages; [
    keyring
    keyring-pass
  ];

  flakeIgnore = [
    "E501" # line too long
  ];
} (builtins.readFile ./git-credential-keyring.py)

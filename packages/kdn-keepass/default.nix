{ lib, pkgs }:
pkgs.writeShellApplication {
  name = "kdn-keepass";
  runtimeInputs = with pkgs; [
    findutils
    expect
    keepassxc
    pass
  ];
  runtimeEnv.expect_script = ./kdn-keepass.exp;
  text = builtins.readFile ./kdn-keepass.sh;
}

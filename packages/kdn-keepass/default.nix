{ lib, pkgs }:
pkgs.writeShellApplication {
  name = "kdn-keepass";
  runtimeInputs = with pkgs; [
    coreutils
    expect
    findutils
    gnugrep
    gron
    keepassxc
    pass
    sway
    systemd
  ];
  runtimeEnv.expect_script = ./kdn-keepass.exp;
  text = builtins.readFile ./kdn-keepass.sh;
}

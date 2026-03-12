{
  lib,
  pkgs,
  ...
}:
pkgs.writeShellApplication {
  name = "kdn-gamingctl";
  runtimeInputs = with pkgs; [
    systemd
    supergfxctl
    libnotify
    sway
  ];
  text = builtins.readFile ./kdn-gamingctl.sh;
}

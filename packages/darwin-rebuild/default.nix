{
  lib,
  pkgs,
  kdnConfig,
  ...
}:
pkgs.writeShellApplication {
  name = "darwin-rebuild";
  runtimeInputs = with pkgs; [
    coreutils
    darwin-rebuild
    nettools
    nix-output-monitor
    openssh
  ];
  text = builtins.readFile "${kdnConfig.self}/darwin-rebuild.sh";
}

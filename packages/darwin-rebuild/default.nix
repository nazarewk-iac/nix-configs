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
  runtimeEnv.DEFAULT_SRC = "${kdnConfig.self}";
  text = builtins.readFile ./darwin-rebuild.sh;
}

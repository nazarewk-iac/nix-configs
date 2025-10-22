{
  pkgs,
  lib,
  ...
}:
pkgs.writeShellApplication {
  name = "kdn-init-py-script";
  runtimeInputs = with pkgs; [
    coreutils
    findutils
    gnused
    git
  ];
  runtimeEnv.template_dir = ./template;
  text = builtins.readFile ./init-py-script.sh;
}

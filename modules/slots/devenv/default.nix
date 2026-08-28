# devenv.sh install slot.
#
# Installs the devenv CLI and wires the interactive-shell hooks. The goal is a drop-in: a
# consumer that only pulls `mkSlots` into a config gets a working devenv setup, without the
# full universal module tree.
#
# Targets all three applicable system contexts:
#   - nixos, darwin -> install pkgs.devenv system-wide and keep devenv GC roots
#   - home          -> install pkgs.devenv for the user and load the devenv shell hook
#
# `keep-outputs`/`keep-derivations` stop the nix garbage collector from removing devenv build
# outputs and derivations. devenv needs them to hold its GC roots.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.devenv;

  # System target (nixos + darwin): the CLI plus the nix settings devenv needs.
  systemModule = {
    environment.systemPackages = [ pkgs.devenv ];
    nix.extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';
  };

  # home-manager target: the CLI for the user plus the devenv shell hook per shell.
  homeModule =
    {
      lib,
      pkgs,
      ...
    }:
    {
      home.packages = [ pkgs.devenv ];
      programs.bash.initExtra = ''
        eval "$(${lib.getExe pkgs.devenv} hook bash)"
      '';
      programs.zsh.initContent = ''
        eval "$(${lib.getExe pkgs.devenv} hook zsh)"
      '';
      programs.fish.interactiveShellInit = ''
        ${lib.getExe pkgs.devenv} hook fish | source
      '';
    };
in
{
  options.kdn.devenv = {
    enable = lib.mkEnableOption "devenv.sh CLI and shell integration";
  };

  config = lib.mkIf cfg.enable {
    nixos = systemModule;
    darwin = systemModule;
    home = homeModule;
  };
}

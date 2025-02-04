{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.nix-utils;
in {
  options.kdn.programs.nix-utils = {
    enable = lib.mkEnableOption "nix management utilities setup";
  };

  config = lib.mkIf cfg.enable {
    programs.fish.interactiveShellInit = ''
      complete -c kdn-nix-which --wraps which
    '';
    environment.systemPackages = with pkgs; [
      nix-derivation # pretty-derivation
      nix-output-monitor
      nix-du
      nix-tree
      kdn.kdn-nix
    ];
  };
}

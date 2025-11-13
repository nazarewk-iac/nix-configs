{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.toolset.nix;
in {
  config = lib.mkIf cfg.enable {
    programs.fish.interactiveShellInit = ''
      complete -c kdn-nix-which --wraps which
    '';
  };
}

{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.ssh-client;
in
{
  options.kdn.programs.ssh-client = {
    enable = lib.mkEnableOption "SSH client configuration";
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    { }
  ]);
}

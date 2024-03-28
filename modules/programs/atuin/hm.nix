# litestream inspired by https://github.com/NixOS/nixpkgs/blob/2726f127c15a4cc9810843b96cad73c7eb39e443/nixos/modules/services/network-filesystems/litestream/default.nix
{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.atuin;
in
{
  options.kdn.programs.atuin = {
    enable = lib.mkEnableOption "Atuin shell history management and sync";
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      programs.atuin.enable = true;
      programs.atuin.settings = {
        auto_sync = true;
        update_check = false;
        sync_frequency = "0";
      };
    }
  ]);
}

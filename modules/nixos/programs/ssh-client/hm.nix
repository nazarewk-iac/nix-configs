# litestream inspired by https://github.com/NixOS/nixpkgs/blob/2726f127c15a4cc9810843b96cad73c7eb39e443/nixos/modules/services/network-filesystems/litestream/default.nix
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.ssh-client;
in {
  options.kdn.programs.ssh-client = {
    enable = lib.mkEnableOption "SSH client configuration";
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.ssh-agent.enable = true;
      programs.ssh.enable = true;
      programs.ssh.includes = [
        "~/.ssh/config.d/*.config"
        "~/.ssh/config.local"
      ];

      kdn.hardware.disks.persist."usr/data".directories = [
        ".ssh"
      ];
    }
  ]);
}

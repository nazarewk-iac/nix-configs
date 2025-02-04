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
      services.ssh-agent.enable = pkgs.stdenv.isLinux;
      programs.ssh.enable = true;
      programs.ssh.includes = [
        "~/.ssh/config.d/*.config"
        "~/.ssh/config.local"
      ];

      kdn.hw.disks.persist."usr/data".directories = [
        ".ssh"
      ];
    }
  ]);
}

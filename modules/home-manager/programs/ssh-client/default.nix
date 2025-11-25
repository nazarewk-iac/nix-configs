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
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.ssh-agent.enable = pkgs.stdenv.isLinux;

        programs.ssh.enable = true;
        programs.ssh.includes = [
          "~/.ssh/config.d/*.config"
          "~/.ssh/config.local"
        ];

        kdn.disks.persist."usr/data".directories = [
          ".ssh"
        ];
      }
      {
        # provide my own 9slightly modified) default
        # handle deprecation of defaults at https://github.com/nix-community/home-manager/blob/f3d3b4592a73fb64b5423234c01985ea73976596/modules/programs/ssh.nix#L650-L655
        programs.ssh.enableDefaultConfig = false;
        programs.ssh.matchBlocks."*" = {
          forwardAgent = lib.mkDefault false;
          addKeysToAgent = lib.mkDefault "no";
          compression = lib.mkDefault false;
          serverAliveInterval = lib.mkDefault 15;
          serverAliveCountMax = lib.mkDefault 3;
          hashKnownHosts = lib.mkDefault false;
          userKnownHostsFile = lib.mkDefault "~/.ssh/known_hosts";
          controlMaster = lib.mkDefault "auto";
          controlPath = lib.mkDefault "~/.ssh/master-%r@%n:%p";
          controlPersist = lib.mkDefault "1m";
        };
      }
    ]
  );
}

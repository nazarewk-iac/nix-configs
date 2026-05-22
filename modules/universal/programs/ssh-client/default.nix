{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.ssh-client;
in
{
  options.kdn.programs.ssh-client = {
    enable = lib.mkEnableOption "SSH client configuration";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHM (
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
            # provide my own slightly modified default
            # handle deprecation of defaults at https://github.com/nix-community/home-manager/blob/f3d3b4592a73fb64b5423234c01985ea73976596/modules/programs/ssh.nix#L650-L655
            programs.ssh.enableDefaultConfig = false;
            programs.ssh.settings."*" = {
              ForwardAgent = lib.mkDefault false;
              AddKeysToAgent = lib.mkDefault "no";
              Compression = lib.mkDefault false;
              ServerAliveInterval = lib.mkDefault 15;
              ServerAliveCountMax = lib.mkDefault 3;
              HashKnownHosts = lib.mkDefault false;
              UserKnownHostsFile = lib.mkDefault "~/.ssh/known_hosts";
              ControlMaster = lib.mkDefault "auto";
              ControlPath = lib.mkDefault "~/.ssh/master-%r@%n:%p";
              ControlPersist = lib.mkDefault "5m";
            };
          }
          (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "darwin" ]) {
            # TODO: try to determine it more gracefully if possible?
            programs.ssh.package = pkgs.openssh;
          })
        ]
      ))
    ]
  );
}

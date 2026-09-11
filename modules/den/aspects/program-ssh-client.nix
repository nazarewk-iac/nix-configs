# `kdn.programs.ssh-client`, as a den aspect.
# It ports `modules/universal/programs/ssh-client/default.nix`.
#
# `services.ssh-agent.enable` keeps its `lib.mkDefault`. The `ssh-agent` aspect writes a plain `true`,
# so the two compose and the plain value wins.
#
# The old module writes the `.ssh` persist entry through `kdn.disks.persist`. This aspect routes it
# through `kdn.apps.ssh` instead, so it needs no disks aspect.
{ kdn, ... }:
{
  kdn.program-ssh-client.includes = [ kdn.apps ];

  kdn.program-ssh-client.homeManager =
    { lib, pkgs, ... }:
    {
      config = lib.mkMerge [
        {
          # A `lib.mkDefault`, so the `ssh-agent` aspect can turn the agent on for macOS too.
          # Upstream home-manager `services.ssh-agent` supports macOS through launchd.
          services.ssh-agent.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isLinux;

          programs.ssh.enable = true;
          programs.ssh.includes = [
            "~/.ssh/config.d/*.config"
            "~/.ssh/config.local"
          ];

          kdn.apps.ssh = {
            enable = true;
            package.original = pkgs.openssh;
            # `programs.ssh` installs the client itself.
            package.install = false;
            # The leading `/` makes the path relative to the home directory.
            dirs.data = [ "/.ssh" ];
          };
        }
        {
          # One slightly modified default set. It handles the home-manager deprecation of the
          # built-in defaults. See
          # https://github.com/nix-community/home-manager/blob/f3d3b4592a73fb64b5423234c01985ea73976596/modules/programs/ssh.nix#L650-L655
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
        (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          # macOS ships an old OpenSSH. The nixpkgs build supports the options above.
          programs.ssh.package = pkgs.openssh;
        })
      ];
    };
}

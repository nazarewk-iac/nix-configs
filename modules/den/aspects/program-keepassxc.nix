# `kdn.programs.keepassxc`, as a den aspect.
# It ports `modules/universal/programs/keepassxc/default.nix`.
#
# ## The defect this port does not reproduce
#
# The old module reads `hasParentOfAnyType [ "nixos" ]` to decide whether `kdn-keepass` reaches the
# package list. That guard tests the parent chain, and the chain is empty on a NixOS host, so the
# package never reaches `environment.systemPackages`. The real intent is "Linux, in either context".
# This aspect uses `pkgs.stdenv.hostPlatform.isLinux`. A separate change fixes the old tree, so the
# two edits touch different files and cannot collide.
#
# ## Two renames the aspect rules force
#
# `service.enable` is a reachable `enable` option, so it becomes `service.use`. The old
# `kdn.programs.keepassxc.enable` disappears: inclusion is the switch.
#
# ## Three defaults the old module leaves out
#
# `service.searchDirs` and `service.fileName` carry no default in the old tree, so a host that turns
# the service on without them fails at evaluation. Both get one here.
#
# ## The browser hosts stay optional
#
# The old module writes `kdn.programs.firefox.nativeMessagingHosts` and the thunderbird twin
# unconditionally. An `includes` of both aspects would pull two browsers into every subject that
# wants a password manager. So the writes test the option tree instead, and they fire only when the
# consumer already includes that aspect.
{ kdn, ... }:
{
  kdn.program-keepassxc.includes = [ kdn.apps ];

  kdn.program-keepassxc.homeManager =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.keepassxc;

      envs.KEEPASS_PATH = builtins.concatStringsSep ":" cfg.service.searchDirs;

      finalPackage = config.kdn.apps.keepassxc.package.final;

      # A plain `callPackage` route, with no overlay. `pkgs.kdn.kdn-keepass` needs this repository's
      # own overlay, and a relative path literal needs none.
      kdn-keepass = pkgs.callPackage ../../../packages/kdn-keepass { };

      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      options.kdn.programs.keepassxc.service.use = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run keepassxc as a user service, through the `kdn-keepass` wrapper.

          The old module names this option `service.enable`. An aspect holds no reachable `enable`,
          so the name changed and the behaviour did not.
        '';
      };

      options.kdn.programs.keepassxc.service.searchDirs = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = ''
          Directories the wrapper searches for the database file. The aspect joins them with `:` into
          `KEEPASS_PATH`, and it makes each one a `ConditionPathExists` of the unit.
        '';
      };

      options.kdn.programs.keepassxc.service.fileName = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Name of the database file the wrapper opens. The wrapper looks for it in every
          `service.searchDirs` entry.
        '';
      };

      config = lib.mkMerge [
        {
          kdn.apps.keepassxc = {
            enable = true;
            # The cache directory holds the browser integration config.
            dirs.cache = [ "keepassxc" ];
            dirs.config = [ "keepassxc" ];
            dirs.state = [ "keepassxc" ];
          };

          home.packages = filterPackages (lib.optional pkgs.stdenv.hostPlatform.isLinux kdn-keepass);
        }

        # Each write below reaches a sibling aspect's own option, and only when that aspect is part
        # of the same evaluation. See the header.
        (lib.optionalAttrs (options.kdn.programs ? firefox) {
          kdn.programs.firefox.nativeMessagingHosts = [ finalPackage ];
        })
        (lib.optionalAttrs (options.kdn.programs ? thunderbird) {
          kdn.programs.thunderbird.nativeMessagingHosts = [ finalPackage ];
        })

        (lib.mkIf cfg.service.use {
          home.sessionVariables = envs;

          systemd.user.services.keepassxc = {
            Unit.Description = "KeePassXC password manager";
            Unit.ConditionPathExists = cfg.service.searchDirs;
            Unit.Wants = [ "ssh-agent.service" ];
            Service = {
              Slice = "background.slice";
              Type = "notify";
              NotifyAccess = "all";
              Environment = lib.attrsets.mapAttrsToList (key: value: "${key}=${value}") envs;
              ExecStart = lib.strings.escapeShellArgs [
                (lib.getExe kdn-keepass)
                cfg.service.fileName
              ];
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
        })
      ];
    };
}

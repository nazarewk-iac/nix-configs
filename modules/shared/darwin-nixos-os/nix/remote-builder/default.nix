{
  lib,
  pkgs,
  config,
  self,
  ...
}: let
  cfg = config.kdn.nix.remote-builder;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      /*
      WARNING: options need to be supported both by nix-darwin and NixOS:
      - https://daiderd.com/nix-darwin/manual/index.html#opt-users.users._name_.name
      - https://search.nixos.org/options?channel=24.11&from=0&size=50&sort=alpha_asc&type=packages&query=users.users
      */
      nix.settings.trusted-users = [
        cfg.user.name
      ];
      users.groups."${cfg.group.name}" = {
        gid = cfg.group.id;
        description = cfg.description;
      };
      users.users."${cfg.user.name}" = {
        uid = cfg.user.id;
        gid = cfg.group.id;
        description = cfg.description;
        createHome = false;
        isHidden = true;
        # TODO: create a shared SSH key for `root` user with sops and add it here
        openssh.authorizedKeys.keyFiles = [
          config.kdn.profile.user.kdn.ssh.authorizedKeysPath
        ];
      };
    }
  ]);
}

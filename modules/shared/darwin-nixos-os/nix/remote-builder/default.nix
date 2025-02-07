{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.nix.remote-builder;
in {
  config = lib.mkMerge [
    (lib.mkIf cfg.enable (lib.mkMerge [
      {
        /*
        WARNING: options need to be supported both by nix-darwin and NixOS:
        - https://daiderd.com/nix-darwin/manual/index.html#opt-users.users._name_.name
        - https://search.nixos.org/options?channel=24.11&from=0&size=50&sort=alpha_asc&type=packages&query=users.users
        */
        nix.settings.trusted-users = [
          "@${cfg.group.name}"
        ];
        users.groups."${cfg.group.name}" = {
          gid = cfg.group.id;
        };
        users.users."${cfg.user.name}" = lib.mkMerge [
          {
            uid = cfg.user.id;
            description = cfg.description;
            createHome = false;
            openssh.authorizedKeys.keyFiles = [
              config.kdn.profile.user.kdn.ssh.authorizedKeysPath
            ];
          }
          (lib.mkIf (builtins.elem "nix-darwin" config.kdn.types) {
            description = cfg.description;
            gid = cfg.group.id;
            isHidden = true;
          })
          (lib.mkIf (builtins.elem "nixos" config.kdn.types) {
            isSystemUser = true;
            group = cfg.group.name;
          })
        ];
      }
    ]))
    (lib.mkIf cfg.use (lib.mkMerge [
      {
        programs.ssh.extraConfig = let
          file = pkgs.writeText "ssh-config-kdn-nix-remote-build" ''
            Match User ${cfg.user.name}
              BatchMode yes
              IdentitiesOnly yes
              IdentityFile ${cfg.user.ssh.IdentityFile}
          '';
        in
          lib.mkBefore "Include ${file}";
      }
    ]))
  ];
}

{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.atuin;

  users = lib.pipe cfg.users [
    (builtins.map (username:
      let
        user = config.users.users."${username}";
        tmp.history = "/run/user/${toString user.uid}/atuin/history.db";
        tmp.records = "/run/user/${toString user.uid}/atuin/records.db";

        litestream.config =
          let
            mkReplica = type: {
              path = "${user.home}/.local/share/atuin/litestream/${type}";
              validation-interval = "1m";
              snapshot-interval = "1h";
              retention = "6h";
            };
          in
          {
            dbs = [
              { path = tmp.history; replicas = [ (mkReplica "history") ]; }
              { path = tmp.records; replicas = [ (mkReplica "records") ]; }
            ];
          };
        litestream.configPath = (pkgs.formats.yaml { }).generate "atuin-litestream-config-${username}.yaml" litestream.config;
        litestream.cmd = cmd: args: lib.escapeShellArgs ([ (lib.getExe pkgs.litestream) cmd "-config" litestream.configPath ] ++ args);
      in
      lib.nameValuePair username {
        uid = user.uid;
        litestream.restores = builtins.map
          (db: litestream.cmd "restore" [ "-if-replica-exists" "-if-db-not-exists" db.path ])
          litestream.config.dbs;
        litestream.replicate = litestream.cmd "replicate" [ ];
        atuin.settings = {
          db_path = tmp.history;
          # 2024-03-28: not documented, but present in https://github.com/atuinsh/atuin/blob/82a7c8d3219749dd298b23bae22456657ee92575/atuin-client/src/settings.rs#L590C1-L590C13
          record_store_path = tmp.records;
        };
      }))
    builtins.listToAttrs
  ];
in
{
  options.kdn.programs.atuin = {
    enable = lib.mkEnableOption "Atuin shell history management and sync";
    enableZFSWorkaround = lib.mkOption {
      type = with lib.types; bool;
      default = true;
    };
    users = lib.mkOption {
      type = with lib.types; listOf str;
    };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      /* TODO: implement automated atuin login:
           - store the data on a tmpfs mount under user's home (will require ~64MB+ space)
           - retrieve credentials from `sops-nix`
           - log in
           - run the first sync
       */
      kdn.programs.atuin.users = [ "root" ];
      home-manager.users = builtins.mapAttrs
        (_:_: {
          kdn.programs.atuin.enable = true;
          home.persistence."usr/data".directories = [ ".local/share/atuin" ];
        })
        users;
    }
    (lib.mkIf cfg.enableZFSWorkaround {
      environment.systemPackages = with pkgs;[ litestream ];
      home-manager.users = builtins.mapAttrs (_:user: { programs.atuin.settings = user.atuin.settings; }) users;
      systemd.services = lib.attrsets.mapAttrs'
        (username: user:
          lib.nameValuePair "atuin-zfs-workaround-${username}" {
            wantedBy = [ "multi-user.target" ];
            requires = [ "user-runtime-dir@${toString user.uid}.service" ];
            after = [ "user-runtime-dir@${toString user.uid}.service" ];
            description = "Synchronize Atuin database on tmpfs for ${username}";

            serviceConfig.User = username;
            serviceConfig.ExecStartPre = user.litestream.restores;
            serviceConfig.ExecStart = user.litestream.replicate;
          })
        users;
    })
  ]);
}

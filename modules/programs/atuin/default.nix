{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.atuin;

  getRuntimeDir = username:
    let user = config.users.users."${username}";
    in "/run/user/${toString user.uid}/atuin";
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
    autologinUsers = lib.mkOption {
      type = with lib.types; listOf str;
    };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.programs.atuin.users = [ "root" ];
      kdn.programs.atuin.autologinUsers = [ "root" ];
      home-manager.users = lib.pipe cfg.users [
        (builtins.map (username: {
          name = username;
          value = {
            kdn.programs.atuin.enable = true;
            home.persistence."usr/data".directories = [ ".local/share/atuin" ];
            programs.atuin.settings = {
              daemon.socket_path = "${getRuntimeDir username}/atuin.sock";
            };
          };
        }))
        builtins.listToAttrs
      ];
    }
    (lib.mkIf cfg.enableZFSWorkaround (
      let
        users = lib.pipe cfg.users [
          (builtins.map (username:
            let
              user = config.users.users."${username}";
              tmp.history = "${getRuntimeDir username}/history.db";
              tmp.records = "${getRuntimeDir username}/records.db";

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
        environment.systemPackages = with pkgs;[ litestream ];
        home-manager.users = builtins.mapAttrs (_:user: { programs.atuin.settings = user.atuin.settings; }) users;
        systemd.services = lib.attrsets.mapAttrs'
          (username: user:
            lib.nameValuePair "atuin-zfs-workaround-${username}" {
              wantedBy = [ "default.target" ];
              requires = [ "user-runtime-dir@${toString user.uid}.service" ];
              after = [ "user-runtime-dir@${toString user.uid}.service" ];
              description = "Synchronize Atuin database on tmpfs for ${username}";

              serviceConfig.User = username;
              serviceConfig.ExecStartPre = user.litestream.restores;
              serviceConfig.ExecStart = user.litestream.replicate;
            })
          users;
      }
    ))
    (lib.mkIf (builtins.elem "root" cfg.users) {
      systemd.services.atuind = {
        description = "Atuin shell history synchronization daemon for root user";
        after = [ "network-online.target" ];
        requires = [ "network-online.target" ];
        wantedBy = [ "default.target" ];
        environment.HOME = config.users.users.root.home;
        environment.ATUIN_LOG = "info";
        serviceConfig.ExecStart = "${lib.getExe pkgs.atuin} daemon";
      };
    })
    (lib.mkIf config.kdn.security.secrets.enable {
      systemd.services = lib.pipe cfg.autologinUsers [
        (builtins.map (username: {
          name = "kdn-atuin-login-${username}";
          value = {
            wantedBy = [ "network-online.target" ];
            after = [ "network-online.target" ];
            requires = [ "network-online.target" ];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };

            script =
              let
                user = config.users.users."${username}";
                secrets = config.sops.secrets;
              in
              ''
                export PATH="${lib.makeBinPath (with pkgs; [coreutils gnugrep])}:$PATH"

                atuin() {
                  /run/wrappers/bin/sudo -u '${username}' '${lib.getExe pkgs.atuin}' "$@"
                }

                if atuin status | grep -v 'You are not logged in' ; then
                  exit 0
                fi

                echo 'Logging in...'
                atuin account login \
                    -u "$(cat '${secrets."default/atuin/username".path}')" \
                    -p "$(cat '${secrets."default/atuin/password".path}')" \
                    -k "$(cat '${secrets."default/atuin/key".path}')"

                echo 'Syncing...'
                atuin sync --force

                echo 'Finished.'
              '';
          };
        }))
        builtins.listToAttrs
      ];
    })
  ]);
}

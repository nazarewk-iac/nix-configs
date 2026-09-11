# `kdn.programs.atuin`, as a den aspect. It ports `modules/universal/programs/atuin/default.nix`.
#
# The litestream part follows
# https://github.com/NixOS/nixpkgs/blob/2726f127c15a4cc9810843b96cad73c7eb39e443/nixos/modules/services/network-filesystems/litestream/default.nix
#
# ## Why the ZFS workaround needs one option
#
# The old module computes the two temporary database paths on the host, from the user's uid, and then
# pushes them into the user config through `home-manager.users`. den holds no bridge from a host class
# into a user class, so `runtimeDir` carries the value. The `nixos` target computes the path for its
# own units. A consumer sets the same value in the user's own config, where it knows the uid.
#
# ## Three secret reads the port replaces
#
# The old module reads `config.sops.secrets."default/atuin/{username,password,key}"` and
# `config.kdn.security.secrets.allowed`. An aspect names no secret store. Three `nullOr path` options
# take their place, and the login service exists only when all three hold a path.
#
# ## Two defaults the old module leaves out
#
# `users` and `autologinUsers` carry no default in the old tree; a separate branch assigns
# `[ "root" ]` when the module is on. The defaults move onto the options here.
{ kdn, ... }:
let
  declaration =
    { lib, ... }:
    {
      options.kdn.programs.atuin.enableZFSWorkaround = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Keep the atuin databases on tmpfs and replicate them with litestream.

          ZFS makes the SQLite write path slow enough to stall every shell prompt. The workaround moves
          the live database to the runtime directory and streams it back to the home directory.
        '';
      };

      options.kdn.programs.atuin.users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "root" ];
        description = ''
          Users that get the ZFS workaround units.

          Two plain definitions of this list concatenate. Never put `lib.mkDefault` on it — a plain
          definition then replaces the default instead of adding to it.
        '';
      };

      options.kdn.programs.atuin.autologinUsers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "root" ];
        description = ''
          Users that get a one-shot login unit. It needs all three `autologin.*File` options.

          Two plain definitions of this list concatenate. Never put `lib.mkDefault` on it.
        '';
      };

      options.kdn.programs.atuin.runtimeDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/run/user/1000/atuin";
        description = ''
          Directory that holds the live databases while the ZFS workaround runs.

          The `nixos` target computes this path per user from the uid. A user evaluation cannot read a
          uid, so a consumer repeats the value here to point `db_path` at the same place.

          The type is `nullOr`, so a `lib.mkOptionDefault` cannot neutralise the default. Use
          `lib.mkOverride 1400` when a consumer must un-set it.
        '';
      };

      options.kdn.programs.atuin.autologin.usernameFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File that holds the atuin account name. `null` turns the login unit off.";
      };

      options.kdn.programs.atuin.autologin.passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File that holds the atuin account password. `null` turns the login unit off.";
      };

      options.kdn.programs.atuin.autologin.keyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File that holds the atuin sync key. `null` turns the login unit off.";
      };

      options.kdn.programs.atuin.autologin.extraUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "kdn-secrets.target" ];
        description = ''
          Units the login unit requires and starts after. A secret store names its own target here.

          Two plain definitions of this list concatenate. Never put `lib.mkDefault` on it.
        '';
      };
    };
in
{
  kdn.program-atuin.includes = [ kdn.apps ];

  kdn.program-atuin.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.atuin;

      getRuntimeDir = username: "/run/user/${toString config.users.users.${username}.uid}/atuin";

      hasAutologinCreds =
        cfg.autologin.usernameFile != null
        && cfg.autologin.passwordFile != null
        && cfg.autologin.keyFile != null;

      workaroundUsers = lib.pipe cfg.users [
        (map (
          username:
          let
            user = config.users.users.${username};
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
                  {
                    path = tmp.history;
                    replicas = [ (mkReplica "history") ];
                  }
                  {
                    path = tmp.records;
                    replicas = [ (mkReplica "records") ];
                  }
                ];
              };
            litestream.configPath =
              (pkgs.formats.yaml { }).generate "atuin-litestream-config-${username}.yaml"
                litestream.config;
            litestream.cmd =
              cmd: args:
              lib.escapeShellArgs (
                [
                  (lib.getExe pkgs.litestream)
                  cmd
                  "-config"
                  litestream.configPath
                ]
                ++ args
              );
          in
          lib.nameValuePair username {
            uid = user.uid;
            litestream.restores = map (
              db:
              litestream.cmd "restore" [
                "-if-replica-exists"
                "-if-db-not-exists"
                db.path
              ]
            ) litestream.config.dbs;
            litestream.replicate = litestream.cmd "replicate" [ ];
          }
        ))
        builtins.listToAttrs
      ];
    in
    {
      imports = [ declaration ];

      config = lib.mkMerge [
        (lib.mkIf cfg.enableZFSWorkaround {
          environment.systemPackages = [ pkgs.litestream ];

          systemd.services = lib.mapAttrs' (
            username: user:
            lib.nameValuePair "atuin-zfs-workaround-${username}" {
              wantedBy = [ "default.target" ];
              requires = [ "user-runtime-dir@${toString user.uid}.service" ];
              after = [ "user-runtime-dir@${toString user.uid}.service" ];
              description = "Synchronize Atuin database on tmpfs for ${username}";

              serviceConfig.User = username;
              serviceConfig.ExecStartPre = user.litestream.restores;
              serviceConfig.ExecStart = user.litestream.replicate;
            }
          ) workaroundUsers;
        })

        (lib.mkIf (builtins.elem "root" cfg.users) {
          systemd.services.atuin-daemon = {
            description = "Atuin shell history synchronization daemon for root user";
            # `home-manager-root` must run first, so the daemon finds its own configuration. Without
            # that order the socket lands in the wrong place.
            after = [
              "network-online.target"
              "home-manager-root.service"
            ];
            requires = [
              "network-online.target"
              "home-manager-root.service"
            ];
            wantedBy = [ "default.target" ];
            environment.HOME = config.users.users.root.home;
            environment.ATUIN_LOG = "info";
            serviceConfig.ExecStart = "${lib.getExe pkgs.atuin} daemon start";
            serviceConfig.ExecStartPre = "-${lib.getExe' pkgs.coreutils "rm"} ${config.users.users.root.home}/.local/share/atuin/atuin.sock";
          };
        })

        (lib.mkIf hasAutologinCreds {
          systemd.services = lib.pipe cfg.autologinUsers [
            (map (
              username:
              lib.nameValuePair "kdn-atuin-login-${username}" {
                wantedBy = [ "network-online.target" ];
                after = [ "network-online.target" ] ++ cfg.autologin.extraUnits;
                requires = [ "network-online.target" ] ++ cfg.autologin.extraUnits;

                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  User = username;

                  LoadCredential = [
                    "username:${cfg.autologin.usernameFile}"
                    "password:${cfg.autologin.passwordFile}"
                    "key:${cfg.autologin.keyFile}"
                  ];
                };

                environment.CREDS_DIR = "%d";

                script = ''
                  export PATH="${
                    lib.makeBinPath (
                      with pkgs;
                      [
                        coreutils
                        diffutils
                        gnugrep
                        atuin
                      ]
                    )
                  }:$PATH"
                  set -eEuo pipefail

                  if ! cmp --silent -- <(atuin key) "$CREDS_DIR/key" ; then
                    atuin logout || :
                    atuin store purge
                  elif atuin status | grep -v 'You are not logged in' || test -s "${
                    config.users.users.${username}.home
                  }/.local/share/atuin/session" ; then
                    exit 0
                  fi

                  echo 'Logging in...'
                  atuin account login \
                      -u "$(cat "$CREDS_DIR/username")" \
                      -p "$(cat "$CREDS_DIR/password")" \
                      -k "$(cat "$CREDS_DIR/key")"

                  echo 'Syncing...'
                  atuin store pull --page=5000 || :

                  echo 'Finished.'
                '';
              }
            ))
            builtins.listToAttrs
          ];
        })
      ];
    };

  kdn.program-atuin.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.programs.atuin;
    in
    {
      imports = [ declaration ];

      config = lib.mkMerge [
        {
          programs.atuin.enable = true;
          programs.atuin.daemon.enable = config.home.username != "root";
          programs.atuin.daemon.logLevel = "info";
          programs.atuin.settings = {
            auto_sync = true;
            update_check = false;
            sync.records = true;
            sync_frequency = "60";
            daemon = {
              enabled = true;
              sync_frequency = 300;
            };
          };
          programs.atuin.forceOverwriteSettings = true;

          kdn.apps.atuin = {
            enable = true;
            # `programs.atuin` installs the package.
            package.install = false;
            dirs.data = [ "atuin" ];
          };
        }

        # The user half of the ZFS workaround. The live databases sit in the runtime directory, and the
        # host units replicate them back into the home directory.
        (lib.mkIf (cfg.enableZFSWorkaround && cfg.runtimeDir != null) {
          programs.atuin.settings.db_path = "${cfg.runtimeDir}/history.db";
          # 2024-03-28: undocumented, but present at
          # https://github.com/atuinsh/atuin/blob/82a7c8d3219749dd298b23bae22456657ee92575/atuin-client/src/settings.rs#L590
          programs.atuin.settings.record_store_path = "${cfg.runtimeDir}/records.db";
        })

        (lib.mkIf (config.home.username != "root") {
          systemd.user.services.atuin-daemon = {
            Unit.After = [ "network.target" ];
            Unit.Wants = [ "network.target" ];
            Service.Slice = "background.slice";
          };
        })

        # nix-darwin Home Manager uses launchd, not systemd. `RunAtLoad` starts the agent on load.
        #
        # atuin does not unlink a stale Unix socket before it binds. A daemon that exits without a clean
        # shutdown (a hard kill, a crash, a power loss) leaves the socket file behind. The next start
        # then fails with "Address already in use (os error 48)", and the launchd `KeepAlive` restart
        # loop never recovers. The wrapper removes the stale socket first, then execs the daemon.
        # home-manager wraps this in its own `wait4path` guard.
        (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
          let
            socketPath =
              config.programs.atuin.settings.daemon.socket_path or "${config.xdg.dataHome}/atuin/daemon.sock";
            atuinDaemonWrapper = pkgs.writeShellScript "atuin-daemon-start" ''
              set -eu
              if test -S ${lib.escapeShellArg socketPath}; then
                rm -f ${lib.escapeShellArg socketPath}
              fi
              exec ${lib.getExe config.programs.atuin.package} daemon start
            '';
          in
          {
            launchd.agents.atuin-daemon.config.RunAtLoad = true;
            launchd.agents.atuin-daemon.config.ProgramArguments = lib.mkForce [ "${atuinDaemonWrapper}" ];
          }
        ))
      ];
    };
}

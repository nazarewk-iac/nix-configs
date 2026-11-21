# litestream inspired by https://github.com/NixOS/nixpkgs/blob/2726f127c15a4cc9810843b96cad73c7eb39e443/nixos/modules/services/network-filesystems/litestream/default.nix
{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.atuin;

  getRuntimeDir =
    username:
    let
      user = config.users.users."${username}";
    in
    "/run/user/${toString user.uid}/atuin";
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
  config = lib.mkMerge [
    (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.programs.atuin.users = [ "root" ];
          kdn.programs.atuin.autologinUsers = [ "root" ];
        }
      ]
    ))
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            programs.atuin.enable = true;
            programs.atuin.daemon.enable = config.home.username != "root";
            programs.atuin.daemon.logLevel = "info";
            programs.atuin.settings = {
              auto_sync = true;
              update_check = false;
              sync.records = true;
              sync_frequency = "60";
              # Atuin 18.24+ Threads: capture AI coding-agent sessions into the encrypted record
              # store, so `atuin threads` and `atuin resume` can search and resume them. The daemon
              # is already enabled above. Import existing sessions once with `atuin threads import`.
              threads.capture = true;
              daemon = {
                enabled = true;
                # atuin refuses to rebuild the threads index inline: a `store pull`, `status` or
                # `account login` with the daemon down fails with "no daemon is running; enable
                # `daemon.autostart = true`". The `kdn-atuin-login-<user>` unit runs exactly those
                # commands at boot, outside a shell, so the shell hook cannot start the daemon for it.
                autostart = true;
                sync_frequency = 300;
              };
            };
            programs.atuin.forceOverwriteSettings = true;
          }
          (lib.mkIf (config.home.username != "root") {
            systemd.user.services.atuin-daemon = {
              Unit.After = [ "network.target" ];
              Unit.Wants = [ "network.target" ];
              Service.Slice = "background.slice";
            };
          })
          # nix-darwin HM uses launchd, not systemd. RunAtLoad starts the agent on load.
          # atuin does not unlink a stale Unix socket before bind. A daemon that exits without
          # a clean shutdown (hard kill, crash, power loss) leaves the socket file behind. The
          # next start then fails with "Address already in use (os error 48)", and launchd's
          # KeepAlive restart loop never recovers. The wrapper removes the stale socket first,
          # then execs the daemon. home-manager wraps this in its own wait4path guard.
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
              launchd.agents.atuin-daemon.config.ProgramArguments = lib.mkForce [
                "${atuinDaemonWrapper}"
              ];
            }
          ))
        ]
      )
    ))
    (kdnConfig.util.ifHMParent (
      lib.mkIf cfg.enable {
        home-manager.users = lib.pipe cfg.users [
          (map (username: {
            name = username;
            value = {
              kdn.programs.atuin = cfg;
              kdn.disks.persist."usr/data".directories = [ ".local/share/atuin" ];
            };
          }))
          builtins.listToAttrs
        ];
      }
    ))
    # nixos
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          (lib.mkIf cfg.enableZFSWorkaround (
            let
              users = lib.pipe cfg.users [
                (map (
                  username:
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
                    atuin.settings = {
                      db_path = tmp.history;
                      # 2024-03-28: not documented, but present in https://github.com/atuinsh/atuin/blob/82a7c8d3219749dd298b23bae22456657ee92575/atuin-client/src/settings.rs#L590C1-L590C13
                      record_store_path = tmp.records;
                    };
                  }
                ))
                builtins.listToAttrs
              ];
            in
            {
              kdn.env.packages = with pkgs; [ litestream ];
              home-manager.users = builtins.mapAttrs (_: user: {
                programs.atuin.settings = user.atuin.settings;
              }) users;
              systemd.services = lib.attrsets.mapAttrs' (
                username: user:
                lib.nameValuePair "atuin-zfs-workaround-${username}" {
                  wantedBy = [ "default.target" ];
                  requires = [
                    "user-runtime-dir@${toString user.uid}.service"
                  ];
                  after = [
                    "user-runtime-dir@${toString user.uid}.service"
                  ];
                  description = "Synchronize Atuin database on tmpfs for ${username}";

                  serviceConfig.User = username;
                  serviceConfig.ExecStartPre = user.litestream.restores;
                  serviceConfig.ExecStart = user.litestream.replicate;
                }
              ) users;
            }
          ))
          (lib.mkIf (builtins.elem "root" cfg.users) {
            systemd.services.atuin-daemon = {
              description = "Atuin shell history synchronization daemon for root user";
              # require home-manager-root to give it a chance to set up atuind configuration
              # otherwise the socket is at a wrong place
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
              serviceConfig.ExecStartPre = [
                # `atuin account login` in `kdn-atuin-login-root` starts its own daemon to re-encrypt
                # the store. That daemon keeps the pidfile, so this unit then failed with "daemon
                # already running" and made every switch exit 4. Stop any daemon first; the `-`
                # ignores the "no daemon is running" case.
                "-${lib.getExe pkgs.atuin} daemon stop"
                "-${lib.getExe' pkgs.coreutils "rm"} ${config.users.users.root.home}/.local/share/atuin/atuin.sock"
              ];
            };
          })
          (lib.mkIf config.kdn.security.secrets.allowed {
            systemd.services = lib.pipe cfg.autologinUsers [
              (map (username: {
                name = "kdn-atuin-login-${username}";
                value = {
                  wantedBy = [ "network-online.target" ];
                  after = [
                    "network-online.target"
                    "kdn-secrets.target"
                  ];
                  requires = [
                    "network-online.target"
                    "kdn-secrets.target"
                  ];

                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    User = username;

                    LoadCredential = [
                      "username:${config.sops.secrets."default/atuin/username".path}"
                      "password:${config.sops.secrets."default/atuin/password".path}"
                      "key:${config.sops.secrets."default/atuin/key".path}"
                    ];
                  };

                  environment.CREDS_DIR = "%d";

                  script =
                    let
                      hmUser = config.home-manager.users."${username}";

                      # Deadline for tolerating the threads-index error, see the script below.
                      threadsGraceUntil = "2026-11-28";
                    in
                    ''
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

                      # Root has no atuin config: its Home Manager file is gone, so no `[daemon]`
                      # section exists and atuin cannot reach the root daemon. `store purge` and
                      # `store pull` then finish their work but fail to rebuild the threads index
                      # ("the records changed, but the threads index was not rebuilt"). That exit
                      # failed this unit on every boot, which made every switch exit 4 fleet-wide.
                      # Tolerate exactly that error until the deadline, then fail again, so the
                      # missing root config cannot be forgotten.
                      ATUIN_THREADS_GRACE_UNTIL="${threadsGraceUntil}"

                      atuin_threads_tolerated() {
                        test "$(date -u +%Y%m%d)" -le "''${ATUIN_THREADS_GRACE_UNTIL//-/}"
                      }

                      run_atuin() {
                        local output status=0
                        output="$("$@" 2>&1)" || status=$?
                        printf '%s\n' "$output"
                        if test "$status" -ne 0 ; then
                          case "$output" in
                            *"threads index was not rebuilt"*|*"Threads need the daemon"*)
                              if atuin_threads_tolerated ; then
                                printf 'WARNING: ignoring the atuin threads-index error until %s: root has no atuin config, so it has no [daemon] section\n' "$ATUIN_THREADS_GRACE_UNTIL" >&2
                                return 0
                              fi
                              printf 'ERROR: the atuin threads-index grace period ended on %s; give root an atuin config with a [daemon] section\n' "$ATUIN_THREADS_GRACE_UNTIL" >&2
                              ;;
                          esac
                          return "$status"
                        fi
                      }

                      # A system unit that runs `User=<name>` has no `XDG_RUNTIME_DIR`, so atuin
                      # looked for the daemon socket outside `/run/user/<uid>` and failed with
                      # "a daemon still holds its pidfile ... after 4000ms". `%U` cannot help: in a
                      # system unit it expands to the MANAGER's uid (0). Derive it from the running
                      # user instead, and wait for linger to create the directory at boot.
                      USER_RUNTIME_DIR="/run/user/$(id -u)"
                      for _ in $(seq 1 30); do
                        test -d "$USER_RUNTIME_DIR" && break
                        sleep 1
                      done
                      export XDG_RUNTIME_DIR="$USER_RUNTIME_DIR"

                      # Compare the KEYS, not the byte streams: `atuin key` ends with a newline and
                      # the SOPS secret does not, so `cmp` failed on identical keys and forced a
                      # logout + `store purge` + login on every boot.
                      if [ "$(atuin key)" != "$(cat "$CREDS_DIR/key")" ] ; then
                        atuin logout || :
                        run_atuin atuin store purge
                      elif atuin status | grep -v 'You are not logged in' || test -s "${hmUser.xdg.dataHome}/atuin/session" ; then
                        exit 0
                      fi

                      echo 'Logging in...'
                      run_atuin atuin account login \
                          -u "$(cat "$CREDS_DIR/username")" \
                          -p "$(cat "$CREDS_DIR/password")" \
                          -k "$(cat "$CREDS_DIR/key")"

                      echo 'Syncing...'
                      run_atuin atuin store pull --page=5000 || :

                      echo 'Finished.'
                    '';
                };
              }))
              builtins.listToAttrs
            ];
          })
        ]
      )
    ))
  ];
}

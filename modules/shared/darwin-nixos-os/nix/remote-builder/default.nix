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
            shell = pkgs.bashInteractive;
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
        home-manager.users.root.programs.ssh.extraConfig = ''
          Match User ${cfg.user.name}
            BatchMode yes
            IdentitiesOnly yes
            IdentityFile ${cfg.user.ssh.IdentityFile}
        '';

        nix.distributedBuilds = true;
        nix.buildMachines =
          lib.pipe [
            {
              hostName = "faro";
              systems = ["aarch64-linux"];
              maxJobs = 7;
              speedFactor = 10;
              supportedFeatures = [
                "gccarch-armv8-a"
              ];
              mandatoryFeatures = [];
            }
            {
              hostName = "briv";
              systems = ["aarch64-linux"];
              maxJobs = 2;
              speedFactor = 4;
              supportedFeatures = [
                "gccarch-armv8-a"
              ];
              mandatoryFeatures = [];
            }
            #{
            #  hostName = "etra";
            #  systems = ["x86_64-linux"];
            #  maxJobs = 2;
            #  speedFactor = 4;
            #}
            {
              hostName = "brys";
              systems = ["x86_64-linux"];
              maxJobs = 16;
              speedFactor = 32;
            }
          ] [
            (builtins.filter (builder: config.kdn.hostName != builder.hostName && !(lib.strings.hasPrefix config.kdn.hostName builder.hostName)))
            (builtins.map (old: let
              defaults = {
                protocol = "ssh-ng";
                sshUser = cfg.user.name;
                supportedFeatures = [
                  "nixos-test"
                  "benchmark"
                  "big-parallel"
                  "kvm"
                ];
                mandatoryFeatures = [];
              };
            in
              defaults
              // old
              // {
                supportedFeatures = builtins.concatLists [
                  (defaults.supportedFeatures or [])
                  (old.supportedFeatures or [])
                ];
              }))
            (builtins.map (old: (
              builtins.map
              (
                {
                  domain,
                  factor ? 100,
                }:
                  old
                  // lib.attrsets.optionalAttrs (domain != "") {
                    hostName = "${old.hostName}.${domain}";
                    speedFactor = builtins.floor (old.speedFactor * factor);
                  }
              )
              [
                {
                  domain = "lan.etra.net.int.kdn.im.";
                  factor = 100;
                }
                {
                  domain = "netbird.cloud.";
                  factor = 20;
                }
              ]
            )))
            lib.lists.flatten
          ];
      }
    ]))
  ];
}

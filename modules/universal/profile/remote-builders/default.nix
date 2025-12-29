{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  isCandidate = filename: fileCfg:
    (fileCfg ? path || (fileCfg ? key && fileCfg ? sopsFile)) && (lib.strings.hasPrefix "id_" filename);
  isPubKey = filename: fileCfg: (isCandidate filename fileCfg) && (lib.strings.hasSuffix ".pub" filename);
  isPrivKey = filename: fileCfg: (isCandidate filename fileCfg) && !(lib.strings.hasSuffix ".pub" filename);

  secretCfgs = config.kdn.security.secrets.sops.secrets.ssh;

  pubKeys = builtins.mapAttrs (_: lib.attrsets.filterAttrs isPubKey) secretCfgs;
  privKeys = builtins.mapAttrs (_: lib.attrsets.filterAttrs isPrivKey) secretCfgs;

  authorizedKeysFiles = lib.pipe pubKeys [
    (lib.attrsets.mapAttrsToList (
      username: keys:
        lib.pipe keys [
          builtins.attrValues
          (builtins.map (fileCfg: builtins.replaceStrings [username] ["%u"] fileCfg.path))
        ]
    ))
    lib.lists.flatten
    lib.lists.unique
    (builtins.sort builtins.lessThan)
  ];

  buildMachines =
    lib.pipe
    [
      # TODO: maybe generate the list dynamically with a script instead?

      # TODO: generate it from a flake/nixosConfigurations
      # TODO: replace it with dynamic `ssh-ping` measurements
      # ssh-ping -W2.5 -c10 -i 0 -n briv22 | awk 'BEGIN {FS="(\033\\\[0m|=| )+"} $1 == "Pong" { print $8}
      /*
      builders are chosen based on:
        1. required & supported features
        2. speedFactor
        3. free build slots (maxJobs)
      */
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
      {
        hostName = "etra";
        systems = ["x86_64-linux"];
        maxJobs = 2;
        speedFactor = 4;
      }
      {
        hostName = "brys";
        systems = ["x86_64-linux"];
        maxJobs = 12;
        speedFactor = 32;
      }
      {
        hostName = "oams";
        systems = ["x86_64-linux"];
        maxJobs = 6;
        speedFactor = 10;
      }
      {
        hostName = "anji";
        systems = ["aarch64-darwin" "x86_64-darwin"];
        maxJobs = 4;
        speedFactor = 8; # 4 perf and 4 efficiency cores
      }
      {
        hostName = "anji-linux-builder";
        systems = ["aarch64-linux"];
        maxJobs = 4;
        speedFactor = 6;
      }
    ]
    [
      (builtins.filter (
        builder:
          config.kdn.hostName
          != builder.hostName
          && !(lib.strings.hasPrefix config.kdn.hostName builder.hostName)
      ))
      # TODO: implement the most common "x86_64-linux" builder properly
      (builtins.filter (builder: !(builtins.elem "x86_64-linux" builder.systems)))
      (builtins.map (
        old: let
          defaults = {
            protocol = "ssh-ng";
            sshUser = bCfg.user.name;
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
          }
      ))
      (builtins.map (
        old: (
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
              domain = "priv.nb.net.int.kdn.im.";
              factor = 20;
            }
          ]
        )
      ))
      lib.lists.flatten
      (l:
        l
        ++ lib.lists.optional (bCfg.localhost.publicHostKey != "") (builtins.removeAttrs bCfg.localhost ["enable"]
          // {
            speedFactor = bCfg.localhost.speedFactor * 1000;
          }))
    ];

  bCfg = config.kdn.nix.remote-builder;
  cfg = config.kdn.profile.remote-builders;
in {
  options.kdn.profile.remote-builders = {
    enable = lib.mkEnableOption "remote builders setup";
    buildMachines = lib.mkOption {
      type = with lib.types; listOf attrs;
    };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.nix.remote-builder.enable = lib.mkDefault true;
      kdn.enable = lib.mkDefault true;
      kdn.profile.default-secrets.enable = lib.mkDefault true;
    }
    (lib.mkIf config.kdn.security.secrets.allowed (lib.mkMerge [
      {
        kdn.profile.remote-builders.buildMachines = buildMachines;
      }
      {
        # lays out SSH keys into files (for the remote builder amongths others
        # TODO: cut it out into baseline?
        kdn.security.secrets.sops.files."ssh" = {
          keyPrefix = "nix/ssh";
          sopsFile = "${kdnConfig.self}/default.unattended.sops.yaml";
          basePath = "/run/configs";
          sops.mode = "0440";
          overrides = [
            (
              key: old: let
                filename = builtins.baseNameOf key;
                result =
                  old
                  // {
                    mode =
                      if isPubKey filename old
                      then "0444"
                      else if isPrivKey filename old
                      then "0400"
                      else "0440";
                  };
              in
                result
            )
          ];
        };
      }
      # configuration related to SSH identities/authorized keys and nix remote builder
      {
        kdn.nix.remote-builder.user.ssh.IdentityFile = let
          username = config.kdn.nix.remote-builder.user.name;
          keys = privKeys."${username}";
          anyKey = lib.pipe keys [
            builtins.attrValues
            builtins.head
          ];
        in
          (keys.id_ed25519 or anyKey).path;
      }
      (kdnConfig.util.ifTypes ["nixos" "darwin"] (lib.mkMerge [
        {
          /*
          WARNING: options need to be supported both by nix-darwin and NixOS:
          - https://daiderd.com/nix-darwin/manual/index.html#opt-users.users._name_.name
          - https://search.nixos.org/options?channel=24.11&from=0&size=50&sort=alpha_asc&type=packages&query=users.users
          */
          nix.settings.trusted-users = [
            "@${bCfg.group.name}"
          ];
          users.groups."${bCfg.group.name}" = {
            gid = bCfg.group.id;
          };
          users.users."${bCfg.user.name}" = lib.mkMerge [
            {
              uid = bCfg.user.id;
              shell = pkgs.bashInteractive;
              description = bCfg.description;
              createHome = false;
              openssh.authorizedKeys.keyFiles = [
                config.kdn.profile.user.kdn.ssh.authorizedKeysPath
              ];
            }
            (kdnConfig.util.ifTypes ["darwin"] {
              description = bCfg.description;
              gid = bCfg.group.id;
              isHidden = true;
            })
            (kdnConfig.util.ifTypes ["nixos"] {
              isSystemUser = true;
              group = bCfg.group.name;
            })
          ];
        }
        (kdnConfig.util.ifTypes ["darwin"] {
          users.knownUsers = [bCfg.user.name];
          users.knownGroups = [bCfg.group.name];
          # SSHD on MacOS throws weird errors when encountering symlinks
          services.openssh.extraConfig = lib.pipe authorizedKeysFiles [
            # include the nix-darwin's SSH location
            (keys: keys ++ ["/etc/ssh/nix_authorized_keys.d/%u"])
            (builtins.concatStringsSep " ")
            (keysString: "AuthorizedKeysCommand /etc/ssh/authorized-keys-command ${keysString}")
          ];
          system.activationScripts.preActivation.text = ''
            cp -a ${pkgs.writeShellScript "cat-nofail" ''/bin/cat "$@" || :''} /etc/ssh/authorized-keys-command
          '';
        })
        (kdnConfig.util.ifTypes ["nixos"] {
          services.displayManager.hiddenUsers = [bCfg.user.name];
          services.openssh.authorizedKeysFiles = authorizedKeysFiles;

          services.userborn.enable = lib.mkDefault true;
        })
        (lib.mkIf bCfg.use {
          home-manager.users.root.programs.ssh.matchBlocks."user:${bCfg.user.name}" = {
            identitiesOnly = true;
            identityFile = bCfg.user.ssh.IdentityFile;
          };
          home-manager.sharedModules = [
            {
              config = {
                programs.ssh.matchBlocks."user:${bCfg.user.name}" = {
                  match = "User ${bCfg.user.name}";
                  extraOptions.BatchMode = "yes";
                };
                programs.ssh.matchBlocks.anji-linux-builder = {
                  host = "anji-linux-builder";
                  proxyJump = lib.mkIf (config.kdn.hostName != "anji") "${bCfg.user.name}@anji";
                  user = bCfg.user.name;
                  hostname = "localhost";
                  port = 31022;
                  extraOptions.HostKeyAlias = "anji-linux-builder";
                };
              };
            }
          ];

          nix.distributedBuilds = true;
          nix.buildMachines = cfg.buildMachines;
        })
      ]))
    ]))
  ]);
}

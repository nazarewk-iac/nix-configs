# The `profile/remote-builders` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns a machine into a build-farm member: it declares the builder account and group, the SSH
# identity that the account logs in with, the `nix.buildMachines` list, and the `nix.distributedBuilds`
# switch. It also declares the `ssh` sops file entry that lays the keys out under `/run/configs`.
#
# It is the reader of `./nix-remote-builder.nix`, which declares the option tree and emits no config.
# The two aspects are included together by every host that uses the build farm.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch. `kdn.nix.remote-builder.enable` and
#    `kdn.profile.default-secrets.enable` both become `includes` entries.
# 2. **The builder fleet leaves the module.** The old module holds five hardcoded builder entries
#    and two domain suffixes. A den aspect carries no personal data, so `buildMachines` is an option
#    with an empty default and the consumer supplies its fleet. The brys host reads
#    `../../data/nix-build-machines.nix`, the same value the old list produces.
# 3. **The default `authorizedKeysFiles` is empty.** The old default names
#    `config.kdn.profile.user.kdn.ssh.authorizedKeysPath`, an old-tree option. A den consumer names
#    its own key files.
# 4. **`kdn.env.packages` does not appear here.** The module writes none today.
# 5. **The `ssh` sops entry keeps its overrides.** The old `overrides` list runs `mkBefore` and it
#    encodes one certificate-mode rule; the port keeps both closures verbatim, because the private
#    key must stay `0400` and every public key `0444`.
# 6. **`nix.settings.allowed-users` and the account stay.** They are the security half of the
#    builder role: the account connects to the daemon, so it must be allowed and not trusted.
#
# ## The class list: `nixos` and `darwin`
#
# The old module guards the account with `ifTypes [ "nixos" "darwin" ]` and the OpenSSH and
# userborn branches with `nixos`. Two targets below follow that split. The `programs.ssh`,
# `nix.distributedBuilds` and `nix.buildMachines` writes exist on both classes.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. `use` is not an `enable`: it selects whether
#    this machine is a *client* of the farm, and the old tree turns it off for a builder that only
#    accepts builds.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
{
  kdn.profile-remote-builders.includes = [
    kdn.nix-remote-builder
    kdn.profile-default-secrets
    kdn.security-secrets-sops
  ];

  kdn.profile-remote-builders.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      bCfg = config.kdn.nix.remote-builder;
      cfg = config.kdn.profile-remote-builders;

      sshSecrets =
        if config.kdn.security.secrets.allowed then
          config.kdn.security.secrets.sops.secrets.ssh or { }
        else
          { };

      isCandidate =
        filename: fileCfg:
        (fileCfg ? path || (fileCfg ? key && fileCfg ? sopsFile)) && (lib.strings.hasPrefix "id_" filename);
      isPubKey =
        filename: fileCfg: (isCandidate filename fileCfg) && (lib.strings.hasSuffix ".pub" filename);
      isPrivKey =
        filename: fileCfg: (isCandidate filename fileCfg) && !(lib.strings.hasSuffix ".pub" filename);

      pubKeys = builtins.mapAttrs (_: lib.attrsets.filterAttrs isPubKey) sshSecrets;
      privKeys = builtins.mapAttrs (_: lib.attrsets.filterAttrs isPrivKey) sshSecrets;

      authorizedKeysFiles = lib.pipe pubKeys [
        (lib.attrsets.mapAttrsToList (
          username: keys:
          lib.pipe keys [
            builtins.attrValues
            (map (fileCfg: builtins.replaceStrings [ username ] [ "%u" ] fileCfg.path))
          ]
        ))
        lib.lists.flatten
        lib.lists.unique
        (builtins.sort builtins.lessThan)
      ];
    in
    {
      imports = [ ../common/host-name.nix ];

      options.kdn.profile-remote-builders.buildMachines = lib.mkOption {
        type = with lib.types; listOf attrs;
        default = [ ];
        description = ''
          The builder entries this machine uses, as `nix.buildMachines` accepts them. An empty list
          leaves the option alone; a consumer that supplies a fleet usually sets `use = true` too.
        '';
      };

      options.kdn.profile-remote-builders.authorizedKeysFiles = lib.mkOption {
        type = with lib.types; listOf path;
        default = [ ];
        example = [ "/persist/etc/ssh/authorized_keys.d/kdn-nix-remote-build" ];
        description = "Public-key files that the remote-builder account accepts.";
      };

      config = lib.mkIf config.kdn.security.secrets.allowed (
        lib.mkMerge [
          {
            # Lays the keys out as files, so the builder account and root's SSH can use them.
            kdn.security.secrets.sops.files."ssh" = {
              keyPrefix = "nix/ssh";
              sopsFile = config.kdn.security.secrets.sops.defaultFile;
              basePath = "/run/configs";
              sops.mode = "0440";
              overrides = lib.mkBefore [
                (
                  key: old:
                  let
                    filename = baseNameOf key;
                    result = old // {
                      mode =
                        if isPubKey filename old then
                          "0444"
                        else if isPrivKey filename old then
                          "0400"
                        else
                          "0440";
                    };
                  in
                  result
                )
                # This entry must be here: without it the `ssh/<user>/id_ed25519` key can be
                # widened by the previous rule, and a private key must never be readable.
                (key: old: {
                  mode = if key == "ssh/${bCfg.user.name}/id_ed25519" then "0400" else old.mode or "0440";
                })
              ];
            };

            kdn.nix.remote-builder.user.ssh.IdentityFile =
              let
                keys = privKeys."${bCfg.user.name}" or { empty.path = null; };
                anyKey = lib.pipe keys [
                  builtins.attrValues
                  builtins.head
                ];
              in
              (keys.id_ed25519 or anyKey).path;

            # The system SSH config applies to root too, and the nix daemon runs the build hook as
            # root. A Home Manager block cannot work here: `IdentityFile` reads the sops secrets of
            # the target module type, and that set is empty in the Home Manager context.
            programs.ssh.extraConfig = ''
              Match User ${bCfg.user.name}
                BatchMode yes
                IdentitiesOnly yes
                IdentityFile ${toString bCfg.user.ssh.IdentityFile}
            '';

            # The builder account. It connects to the daemon, so it must be in `allowed-users`. It
            # must NOT be in `trusted-users`: a trusted client sends the derivation through
            # `buildDerivation`, which skips the build hook, so a builder host would build
            # locally and never forward to its own builders. See docs/lix-caveats.md.
            nix.settings.allowed-users = [ "@${bCfg.group.name}" ];
            users.groups."${bCfg.group.name}" = {
              gid = bCfg.group.id;
            };
            users.users."${bCfg.user.name}" = {
              uid = bCfg.user.id;
              shell = pkgs.bashInteractive;
              description = bCfg.description;
              createHome = false;
              openssh.authorizedKeys.keyFiles = cfg.authorizedKeysFiles;
              isSystemUser = true;
              group = bCfg.group.name;
            };

            services.displayManager.hiddenUsers = [ bCfg.user.name ];
            services.openssh.authorizedKeysFiles = authorizedKeysFiles;
            services.userborn.enable = lib.mkDefault true;
          }

          (lib.mkIf bCfg.use {
            nix.distributedBuilds = lib.mkDefault true;
            nix.buildMachines = cfg.buildMachines;
          })
        ]
      );
    };

  # The darwin target. nix-darwin has no `isSystemUser`, no `services.userborn` and no display
  # manager, so it writes the five account keys it does have and keeps the OpenSSH command.
  kdn.profile-remote-builders.darwin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      bCfg = config.kdn.nix.remote-builder;
      cfg = config.kdn.profile-remote-builders;

      sshSecrets =
        if config.kdn.security.secrets.allowed then
          config.kdn.security.secrets.sops.secrets.ssh or { }
        else
          { };

      isCandidate =
        filename: fileCfg:
        (fileCfg ? path || (fileCfg ? key && fileCfg ? sopsFile)) && (lib.strings.hasPrefix "id_" filename);
      isPubKey =
        filename: fileCfg: (isCandidate filename fileCfg) && (lib.strings.hasSuffix ".pub" filename);
      isPrivKey =
        filename: fileCfg: (isCandidate filename fileCfg) && !(lib.strings.hasSuffix ".pub" filename);

      pubKeys = builtins.mapAttrs (_: lib.attrsets.filterAttrs isPubKey) sshSecrets;
      privKeys = builtins.mapAttrs (_: lib.attrsets.filterAttrs isPrivKey) sshSecrets;

      authorizedKeysFiles = lib.pipe pubKeys [
        (lib.attrsets.mapAttrsToList (
          username: keys:
          lib.pipe keys [
            builtins.attrValues
            (map (fileCfg: builtins.replaceStrings [ username ] [ "%u" ] fileCfg.path))
          ]
        ))
        lib.lists.flatten
        lib.lists.unique
        (builtins.sort builtins.lessThan)
      ];
    in
    {
      imports = [ ../common/host-name.nix ];

      options.kdn.profile-remote-builders.buildMachines = lib.mkOption {
        type = with lib.types; listOf attrs;
        default = [ ];
        description = "The builder entries this machine uses, as `nix.buildMachines` accepts them.";
      };

      options.kdn.profile-remote-builders.authorizedKeysFiles = lib.mkOption {
        type = with lib.types; listOf path;
        default = [ ];
        description = "Public-key files that the remote-builder account accepts.";
      };

      config = lib.mkIf config.kdn.security.secrets.allowed (
        lib.mkMerge [
          {
            kdn.security.secrets.sops.files."ssh" = {
              keyPrefix = "nix/ssh";
              sopsFile = config.kdn.security.secrets.sops.defaultFile;
              basePath = "/run/configs";
              sops.mode = "0440";
              overrides = lib.mkBefore [
                (
                  key: old:
                  let
                    filename = baseNameOf key;
                  in
                  old
                  // {
                    mode =
                      if isPubKey filename old then
                        "0444"
                      else if (isCandidate filename old) then
                        "0400"
                      else
                        "0440";
                  }
                )
                (key: old: {
                  mode = if key == "ssh/${bCfg.user.name}/id_ed25519" then "0400" else old.mode or "0440";
                })
              ];
            };

            kdn.nix.remote-builder.user.ssh.IdentityFile =
              let
                keys = privKeys."${bCfg.user.name}" or { empty.path = null; };
                anyKey = lib.pipe keys [
                  builtins.attrValues
                  builtins.head
                ];
              in
              (keys.id_ed25519 or anyKey).path;

            programs.ssh.extraConfig = ''
              Match User ${bCfg.user.name}
                BatchMode yes
                IdentitiesOnly yes
                IdentityFile ${toString bCfg.user.ssh.IdentityFile}
            '';

            nix.settings.allowed-users = [ "@${bCfg.group.name}" ];
            users.groups."${bCfg.group.name}" = {
              gid = bCfg.group.id;
            };
            users.users."${bCfg.user.name}" = {
              uid = bCfg.user.id;
              shell = pkgs.bashInteractive;
              description = bCfg.description;
              createHome = false;
              openssh.authorizedKeys.keyFiles = cfg.authorizedKeysFiles;
              isHidden = true;
              gid = bCfg.group.id;
            };

            users.knownUsers = [ bCfg.user.name ];
            users.knownGroups = [ bCfg.group.name ];
            # SSHD on macOS throws strange errors when it encounters symlinks.
            services.openssh.extraConfig = lib.pipe authorizedKeysFiles [
              (keys: keys ++ [ "/etc/ssh/nix_authorized_keys.d/%u" ])
              (builtins.concatStringsSep " ")
              (keysString: "AuthorizedKeysCommand /etc/ssh/authorized-keys-command ${keysString}")
            ];
            # SSH is the recovery path, so the command sshd runs must not depend on the
            # external store. A nixpkgs `writeShellScript` puts a /nix/store bash in the
            # shebang; when the store volume is unmounted, that command fails and every
            # key login is denied (measured 2026-11-20 on anji). `/bin/sh` is stable.
            system.activationScripts.preActivation.text = ''
              printf '#!/bin/sh\n/bin/cat "$@" || :\n' > /etc/ssh/authorized-keys-command
              chmod 0555 /etc/ssh/authorized-keys-command
            '';
          }

          (lib.mkIf bCfg.use {
            nix.distributedBuilds = lib.mkDefault true;
            nix.buildMachines = cfg.buildMachines;
          })
        ]
      );
    };
}

{
  lib,
  pkgs,
  config,
  kdn,
  ...
}: let
  isCandidate = filename: fileCfg:
    (fileCfg ? path || (fileCfg ? key && fileCfg ? sopsFile))
    && (lib.strings.hasPrefix "id_" filename);
  isPubKey = filename: fileCfg:
    (isCandidate filename fileCfg)
    && (lib.strings.hasSuffix ".pub" filename);
  isPrivKey = filename: fileCfg:
    (isCandidate filename fileCfg)
    && !(lib.strings.hasSuffix ".pub" filename);

  secretCfgs = config.kdn.security.secrets.sops.secrets.ssh;

  pubKeys = builtins.mapAttrs (_: lib.attrsets.filterAttrs isPubKey) secretCfgs;
  privKeys = builtins.mapAttrs (_: lib.attrsets.filterAttrs isPrivKey) secretCfgs;
in {
  config = lib.mkIf (config.kdn.profile.machine.baseline.enable && config.kdn.security.secrets.allowed) (lib.mkMerge [
    {
      # lays out SSH keys into files (for the remote builder amongths others
      # TODO: cut it out into baseline?
      kdn.security.secrets.sops.files."ssh" = {
        keyPrefix = "nix/ssh";
        sopsFile = "${kdn.self}/default.unattended.sops.yaml";
        basePath = "/run/configs";
        sops.mode = "0440";
        overrides = [
          (key: old: let
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
            result)
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

      services.openssh.authorizedKeysFiles = lib.pipe pubKeys [
        (lib.attrsets.mapAttrsToList (username: keys:
          lib.pipe keys [
            builtins.attrValues
            (builtins.map (fileCfg: builtins.replaceStrings [username] ["%u"] fileCfg.path))
          ]))
        lib.lists.flatten
        lib.lists.unique
        (builtins.sort builtins.lessThan)
      ];
    }
  ]);
}

{
  lib,
  config,
  ...
}: let
  cfg = config.kdn.profile.user.kdn;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      users.users.kdn = {
        description = "Krzysztof Nazarewski";
        openssh.authorizedKeys.keys = cfg.ssh.authorizedKeysList;
      };
    }
  ]);
}

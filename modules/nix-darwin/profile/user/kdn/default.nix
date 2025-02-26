{
  lib,
  config,
  ...
}: let
  cfg = config.kdn.profile.user.kdn;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {home-manager.users.kdn.kdn.profile.user.kdn.enable = true;}
    {
      nix-homebrew.user = "kdn";
      users.users.kdn.home = "/Users/kdn";
    }
  ]);
}

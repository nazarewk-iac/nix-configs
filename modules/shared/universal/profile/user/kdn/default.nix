{
  lib,
  config,
  ...
}: let
  cfg = config.kdn.profile.user.kdn;
in {
  options.kdn.profile.user.kdn = {
    enable = lib.mkEnableOption "enable my user profiles";
    ssh = lib.mkOption {
      readOnly = true;
      default = import ./ssh.nix {inherit lib;};
    };
  };
}

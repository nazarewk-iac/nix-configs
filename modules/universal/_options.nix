{
  config,
  lib,
  ...
} @ args: {
  options.kdn = {
    enable = lib.mkEnableOption "basic Nix configs for kdn";

    args = lib.mkOption {
      internal = true;
      readOnly = true;
      default = args;
    };

    hostName = lib.mkOption {
      type = with lib.types; str;
    };

    nixConfig = lib.mkOption {
      readOnly = true;
      default = import ./nix.nix;
    };
  };
}

{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.linux;
in
{
  options.kdn.linux = {
    enable = lib.mkOption {
      type = with lib.types; bool;

      default = cfg.type != null;
      apply =
        enable:
        lib.trivial.throwIf (
          enable && cfg.type == null
        ) "`kdn.linux` enabled, but `kdn.linux.type == null`!" enable;
    };

    type = lib.mkOption {
      type =
        with lib.types;
        enum [
          null
          "nixos"
          "linux-generic"
        ];
      default =
        if pkgs.stdenv.isLinux && config ? system && config.system ? nixos then
          "nixos"
        else if !config.kdn.hm.enable && pkgs.stdenv.isLinux then
          "linux-generic"
        else
          null;
    };
  };

  config.kdn.types = lib.lists.optional (cfg.type != null) cfg.type;
}

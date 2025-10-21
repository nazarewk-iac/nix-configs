{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.hm;
in
{
  options.kdn.hm = {
    enable = lib.mkOption {
      type = with lib.types; bool;

      default = cfg.type != null;
      apply =
        enable:
        lib.trivial.throwIf (
          enable && cfg.type == null
        ) "`kdn.hm` enabled, but `kdn.hm.type == null`!" enable;
    };

    type = lib.mkOption {
      type =
        with lib.types;
        enum [
          null
          "home-manager"
        ];
      default = if config ? home then "home-manager" else null;
    };
  };

  config.kdn.types = lib.lists.optional (cfg.type != null) cfg.type;
}

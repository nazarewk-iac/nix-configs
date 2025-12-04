{lib, ...}: let
  overridablePackageType = pkg:
    lib.types.submodule (args: {
      options.prev = lib.mkOption {
        type = with lib.types; package;
        default = pkg;
      };
      options.overrides = lib.mkOption {
        type = with lib.types; listOf (functionTo (attrsOf anything));
        default = [];
      };
      options.overrideAttrs = lib.mkOption {
        type = with lib.types; listOf (functionTo (attrsOf anything));
        default = [];
      };
      options.final = lib.mkOption {
        type = with lib.types; package;
        default = lib.pipe args.config.prev [
          (pkg:
            pkg.override (
              prev: lib.lists.foldl (old: fn: fn old) prev args.config.overrides
            ))
          (pkg:
            pkg.overrideAttrs (
              prev: lib.lists.foldl (old: fn: fn old) prev args.config.overrideAttrs
            ))
        ];
      };
    });
  mkOverridablePackageOption = pkg: args: lib.mkOption ({type = overridablePackageType pkg;} // args);
in {
  inherit
    overridablePackageType
    mkOverridablePackageOption
    ;
}

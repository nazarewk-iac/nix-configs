{
  lib,
  config,
  options,
  ...
}:
let
  cfg = config.kdn;
  emptyParent = { };
in
{
  options.kdn.inputs = lib.mkOption { default = cfg.parent.inputs; };
  options.kdn.lib = lib.mkOption { default = cfg.parent.lib; };

  options.kdn.self = lib.mkOption { default = cfg.parent.self or cfg.self.inputs; };
  options.kdn.nix-configs = lib.mkOption { default = cfg.parent.nix-configs or cfg.self; };
  options.kdn.parent = lib.mkOption { default = emptyParent; };
  options.kdn.configure = lib.mkOption {
    readOnly = true;
    default =
      module:
      let
        mod = lib.evalModules {
          modules = [
            ./.
            {
              kdn = lib.mkMerge [
                {
                  inherit (cfg) inputs lib self;
                  parent = builtins.removeAttrs config [ "_module" ];
                }
                module
              ];
            }
            (lib.pipe config [
              (
                c:
                c
                // {
                  kdn = builtins.removeAttrs c.kdn [
                    "configure"
                    "hasParentOfAnyType"
                    "isOfAnyType"
                  ];
                }
              )
              (lib.mkOverride 1100)
            ])
          ];
        };
      in
      mod.config;
  };
  options.kdn.isOfAnyType = lib.mkOption {
    readOnly = true;
    default = builtins.elem cfg.moduleType;
  };
  options.kdn.hasParentOfAnyType = lib.mkOption {
    readOnly = true;
    default = types: cfg.parent != emptyParent && cfg.parent.kdn.isOfAnyType types;
  };

  options.kdn.moduleType = lib.mkOption {
    type = with lib.types; str;
  };
  options.kdn.features = {
    rpi4 = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };
    installer = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };
    darwin-utm-guest = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };
    microvm-host = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };
    microvm-guest = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };
  };
}

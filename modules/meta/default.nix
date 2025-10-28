{
  lib,
  config,
  options,
  ...
}: let
  emptyParent = {};
in {
  options.output.mkSubmodule = lib.mkOption {
    readOnly = true;
    default = module: let
      mod = lib.evalModules {
        modules = [
          ./.
          module
          {parent = lib.mkOverride 1099 (builtins.removeAttrs config ["_module"]);}
          (lib.mkOverride 1100 (builtins.removeAttrs config [
            "parents"
            "output"
            "util"
          ]))
        ];
      };
    in {
      kdnMeta = mod;
      kdnConfig = mod.config;
    };
  };

  options.inputs = lib.mkOption {default = config.parent.inputs;};
  options.lib = lib.mkOption {default = config.parent.lib;};
  options.self = lib.mkOption {default = config.parent.self or config.self.inputs;};
  options.nix-configs = lib.mkOption {default = config.parent.nix-configs or config.self;};
  options.parent = lib.mkOption {default = emptyParent;};

  options.parents = lib.mkOption {
    readOnly = true;
    default =
      if config.parent == emptyParent
      then []
      else [config.parent] ++ config.parent.parents;
  };
  options.util.isOfAnyType = lib.mkOption {
    readOnly = true;
    default = builtins.elem config.moduleType;
  };
  options.util.hasParentOfAnyType = lib.mkOption {
    readOnly = true;
    default = types: builtins.any (parent: parent.util.isOfAnyType types) config.parents;
  };

  options.moduleType = lib.mkOption {
    type = with lib.types; str;
  };
  options.features = {
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

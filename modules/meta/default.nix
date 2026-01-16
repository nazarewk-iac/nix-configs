{
  lib,
  config,
  options,
  ...
} @ args: {
  options.output.mkSubmodule = lib.mkOption {
    readOnly = true;
    default = module: let
      mod = lib.evalModules {
        class = "kdn-meta";
        modules = [
          ./.
          module
          {parent = lib.mkOverride 1099 (builtins.removeAttrs config ["_module"]);}
          (lib.mkOverride 1100 (builtins.removeAttrs config [
            "output"
            "parents"
            "specialArgs"
            "util"
          ]))
        ];
      };
    in
      mod.config;
  };

  options.system = lib.mkOption {
    type = with lib.types; str;
  };
  options.moduleType = lib.mkOption {
    type = with lib.types; str;
  };
  options.modules = lib.mkOption {
    type = with lib.types; listOf path;
    default =
      if config.parent != config.util.emptyParent && config.parent.moduleType == config.moduleType
      then config.parent.modules
      else [];
  };
  options.specialArgs = lib.mkOption {
    readOnly = true;
    default = {
      kdnConfig = config;
      lib = config.lib;
    };
  };
  options.inputs = lib.mkOption {default = config.parent.inputs;};
  options.lib = lib.mkOption {default = config.parent.lib;};
  options.self = lib.mkOption {default = config.parent.self or config.self.inputs;};
  options.nix-configs = lib.mkOption {default = config.parent.nix-configs;};
  options.parent = lib.mkOption {default = config.util.emptyParent;};

  options.parents = lib.mkOption {
    internal = true;
    readOnly = true;
    default =
      if config.parent == config.util.emptyParent
      then []
      else [config.parent] ++ config.parent.parents;
  };

  options.util.emptyParent = lib.mkOption {
    internal = true;
    readOnly = true;
    default = null;
  };
  options.util.knownModuleTypes = lib.mkOption {
    internal = true;
    readOnly = true;
    type = with lib.types; listOf str;
    default = ["nixos" "home-manager" "darwin" "nix-on-droid"];
  };
  options.util.isKnownType = lib.mkOption {
    internal = true;
    readOnly = true;
    default = config.util.isOfType config.util.knownModuleTypes;
  };
  options.util.isOfType = lib.mkOption {
    internal = true;
    readOnly = true;
    default = builtins.elem config.moduleType;
  };
  options.util.ifTypes' = lib.mkOption {
    internal = true;
    readOnly = true;
    default = types: forTrue: forFalse:
      if builtins.elem config.moduleType types
      then forTrue
      else forFalse;
  };
  options.util.ifTypes = lib.mkOption {
    internal = true;
    readOnly = true;
    default = types: data: config.util.ifTypes' types data {};
  };
  options.util.ifNotTypes = lib.mkOption {
    internal = true;
    readOnly = true;
    default = types: data: config.util.ifTypes' types {} data;
  };
  options.util.ifHMParent = lib.mkOption {
    internal = true;
    readOnly = true;
    default = config.util.ifTypes ["nixos" "darwin" "nix-on-droid"];
  };
  options.util.ifNotHMParent = lib.mkOption {
    internal = true;
    readOnly = true;
    default = config.util.ifNotTypes ["nixos" "darwin" "nix-on-droid"];
  };
  options.util.ifHM = lib.mkOption {
    internal = true;
    readOnly = true;
    default = config.util.ifTypes ["home-manager"];
  };
  options.util.hasParentOfAnyType = lib.mkOption {
    internal = true;
    readOnly = true;
    default = types: builtins.any (parent: parent.util.isOfType types) config.parents;
  };
  options.util.loadModules = lib.mkOption {
    internal = true;
    readOnly = true;
    default = {
      curFile,
      src,
      extraSuffixes ? [],
      withDefault ? false,
    }: let
      moduleSuffix =
        {
          nixos = "nixos.nix";
          darwin = "darwin.nix";
          home-manager = "hm.nix";
          nix-on-droid = "droid.nix";
        }."${config.moduleType}";

      allFiles = lib.filesystem.listFilesRecursive src;
      suffixes =
        lib.lists.optionals withDefault ["/default.nix"]
        ++ extraSuffixes
        ++ [
          "/${moduleSuffix}"
          ".${moduleSuffix}"
        ];
      suffixMatchers = builtins.map lib.strings.hasSuffix suffixes;
      filteredFiles = builtins.filter (pathValue: let
        pathStr = builtins.toString pathValue;
        matchesSuffixes = builtins.any (fn: fn pathStr) suffixMatchers;
      in
        pathValue != curFile && matchesSuffixes)
      allFiles;
    in
      filteredFiles;
  };
  options.util.args = lib.mkOption {
    internal = true;
    readOnly = true;
    default = args;
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

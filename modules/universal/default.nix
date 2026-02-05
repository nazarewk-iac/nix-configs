{
  config,
  lib,
  pkgs,
  kdnConfig,
  ...
} @ args: {
  imports =
    [
      ./_stylix.nix
    ]
    ++ kdnConfig.util.loadModules {
      curFile = ./default.nix;
      src = ./.;
      suffixes = ["/default.nix"];
    };

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

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.extraSpecialArgs = (kdnConfig.output.mkSubmodule {moduleType = "home-manager";}).specialArgs;
      home-manager.sharedModules = [
        ({kdnConfig, ...}: {
          imports = kdnConfig.util.loadModules {
            curFile = ./default.nix;
            src = ./.;
            suffixes = ["/default.nix" "/hm.nix"];
          };
        })
      ];
    })
  ];
}

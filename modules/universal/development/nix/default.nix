{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.development.nix;
in {
  options.kdn.development.nix = {
    enable = lib.mkEnableOption "nix development/debugging";

    nh.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    nh.flake = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/home/kdn/dev/github.com/nazarewk-iac/nix-configs";
    };
    nh.package = lib.kdn.options.mkOverridablePackageOption pkgs.nh {};
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {kdn.toolset.nix.enable = true;}
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [{kdn.development.nix.enable = true;}];
    })
    (kdnConfig.util.ifNotHMParent (lib.mkMerge [
      {
        kdn.env.packages = with pkgs; ([
            #self.inputs.nixpkgs-update.defaultPackage.${system}
            nixos-anywhere

            # language servers
            nil
            nixd
          ]
          ++ [
            devenv
          ]
          ++ [
            # formatters
            alejandra
            nixfmt-rfc-style
            kdn.kdn-nix-fmt
          ]);
      }
      (lib.mkIf cfg.nh.enable {
        kdn.env.packages = [cfg.nh.package.final];
        kdn.development.nix.nh.package.overrideAttrs = lib.lists.optional (cfg.nh.flake != null) (prev: {
          buildCommand = lib.strings.replaceString "$out/bin/nh" ("$out/bin/nh "
            + lib.strings.escapeShellArgs [
              "--set-default"
              "NH_FLAKE"
              cfg.nh.flake
            ])
          prev.buildCommand;
        });
      })
    ]))
  ]);
}

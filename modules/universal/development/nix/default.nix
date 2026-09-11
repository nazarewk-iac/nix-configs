{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.nix;
in
{
  options.kdn.development.nix = {
    enable = lib.mkEnableOption "nix development/debugging";

    nh.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    nh.flake = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = cfg.flake.path;
    };
    nh.package = lib.kdn.options.mkOverridablePackageOption pkgs.nh { };

    flake.path = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "${config.kdn.profile.user.kdn.homeDir}/dev/github.com/nazarewk-iac/nix-configs";
      defaultText = lib.literalExpression ''"''${config.kdn.profile.user.kdn.homeDir}/dev/github.com/nazarewk-iac/nix-configs"'';
      example = null;
      description = ''
        Path of the flake checkout this machine rebuilds from.

        `null` means the machine names no checkout. Then `nh.flake` carries no value and the
        baseline writes no `/etc/nixos/flake.nix` link. The default reads the primary user's home
        directory, so a tree with no primary user must set this option or `null`.

        A `lib.mkOptionDefault` cannot neutralise this default, because the type is `nullOr`. Use
        `lib.mkOverride 1400` when a consumer must un-set it.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      { kdn.toolset.nix.enable = lib.mkDefault true; }
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.development.nix = cfg; } ];
      })
      (kdnConfig.util.ifHM {
        programs.helix.extraPackages = with pkgs; [
          nil
          nixd
        ];
        programs.helix.languages.language = [
          {
            name = "nix";
            auto-format = true;
            formatter = {
              command = lib.getExe pkgs.kdn.kdn-nix-fmt;
            };
          }
        ];
      })
      (kdnConfig.util.ifNotHMParent (
        lib.mkMerge [
          {
            kdn.env.packages =
              with pkgs;
              (
                [
                  #self.inputs.nixpkgs-update.defaultPackage.${system}
                  nixos-anywhere

                  # language servers
                  nil
                  nixd
                ]
                ++ [
                  # formatters
                  alejandra
                  nixfmt # used to be nixfmt-rfc-style
                  kdn.kdn-nix-fmt
                ]
              );
          }
          (lib.mkIf cfg.nh.enable {
            kdn.env.packages = [ cfg.nh.package.final ];
            kdn.development.nix.nh.package.overrideAttrs = lib.lists.optional (cfg.nh.flake != null) (prev: {
              buildCommand = lib.strings.replaceString "$out/bin/nh" (
                "$out/bin/nh "
                + lib.strings.escapeShellArgs [
                  "--set-default"
                  "NH_FLAKE"
                  cfg.nh.flake
                ]
              ) prev.buildCommand;
            });
          })
        ]
      ))
    ]
  );
}
